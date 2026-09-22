$ErrorActionPreference = 'Stop'

$repo = 'launioncontacto2-hash/rork-conductores'
$branch = 'feat/copilot-cross-test-foundation'
$workflow = 'copilot-restore-human-test-passwords.yml'
$triggerPath = '.github/copilot-restore.trigger'
$secretNames = @('COPILOT_RESTORE_TEMP_PASSWORD')
$passwords = @{}

function Read-TemporaryPassword([string]$email) {
  $secure = Read-Host "Nueva contraseña temporal para $email" -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    if ([string]::IsNullOrWhiteSpace($value)) { throw 'La contraseña no puede estar vacía.' }
    return $value
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    $secure.Dispose()
  }
}

function Set-GitHubSecret([string]$name, [string]$value) {
  $value | gh secret set $name --repo $repo
  if ($LASTEXITCODE -ne 0) { throw "No se pudo registrar el secreto temporal $name." }
}

function Push-RestoreTrigger {
  $bytes = New-Object byte[] 24
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
  $marker = [Convert]::ToBase64String($bytes)
  $content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("restore-request=$marker`n"))
  $body = @{ message = 'chore(copilot): trigger TEST credential restoration'; content = $content; branch = $branch } | ConvertTo-Json -Compress
  $existing = $null
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $existingJson = gh api "repos/$repo/contents/$triggerPath?ref=$branch" 2>$null
    $existingExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($existingExitCode -eq 0 -and $existingJson) { $existing = $existingJson | ConvertFrom-Json }
  elseif ($existingExitCode -ne 1) { throw "Falló la consulta del trigger con código $existingExitCode." }
  if ($existing -and $existing.sha) { $body = (@{ message = 'chore(copilot): trigger TEST credential restoration'; content = $content; branch = $branch; sha = $existing.sha } | ConvertTo-Json -Compress) }
  $result = $body | gh api "repos/$repo/contents/$triggerPath" --method PUT --input - | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0 -or -not $result.commit.sha) { throw 'No se pudo activar el workflow mediante push controlado.' }
  return $result.commit.sha
}

try {
  gh auth status --hostname github.com *> $null
  if ($LASTEXITCODE -ne 0) { throw 'La sesión local de GitHub CLI no está autenticada.' }
  $passwords[$secretNames[0]] = Read-TemporaryPassword 'las tres identidades TEST'
  foreach ($name in $secretNames) { Set-GitHubSecret $name $passwords[$name] }
  $triggerSha = Push-RestoreTrigger
  $runId = $null
  for ($attempt = 0; $attempt -lt 30 -and -not $runId; $attempt++) {
    Start-Sleep -Seconds 2
    $runs = gh run list --repo $repo --branch $branch --limit 20 --json databaseId,status,headBranch,headSha,event | ConvertFrom-Json
    $runId = ($runs | Where-Object { $_.headBranch -eq $branch -and $_.headSha -eq $triggerSha -and $_.event -eq 'push' } | Select-Object -First 1).databaseId
  }
  if (-not $runId) { throw 'No se pudo localizar el run de restauración.' }
  gh run watch $runId --repo $repo --exit-status
  if ($LASTEXITCODE -ne 0) { throw "El workflow de restauración terminó con error (run $runId)." }
  Write-Output 'PASS: credenciales TEST actualizadas mediante workflow administrativo.'
} finally {
  $cleanupFailures = @()
  foreach ($name in $secretNames) {
    $deleted = $false
    for ($attempt = 0; $attempt -lt 3 -and -not $deleted; $attempt++) {
      gh secret delete $name --repo $repo *> $null
      if ($LASTEXITCODE -eq 0) { $deleted = $true; break }
      Start-Sleep -Seconds 2
    }
    if (-not $deleted) { $cleanupFailures += $name }
  }
  foreach ($name in @($passwords.Keys)) { $passwords[$name] = $null }
  $passwords.Clear()
  if ($cleanupFailures.Count -gt 0) { throw "No se pudieron eliminar secretos temporales: $($cleanupFailures -join ', ')" }
}
