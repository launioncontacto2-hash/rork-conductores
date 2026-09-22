$ErrorActionPreference = 'Stop'

$repo = 'launioncontacto2-hash/rork-conductores'
$branch = 'feat/copilot-cross-test-foundation'
$workflow = 'copilot-restore-human-test-passwords.yml'
$triggerPath = '.github/copilot-restore.trigger'
$secretNames = @('COPILOT_RESTORE_JORGE_PASSWORD', 'COPILOT_RESTORE_CONSOLE_PASSWORD', 'COPILOT_RESTORE_SUPERVISION_PASSWORD')
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
  $marker = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
  $content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("restore-request=$marker`n"))
  $body = @{ message = 'chore(copilot): trigger TEST credential restoration'; content = $content; branch = $branch } | ConvertTo-Json -Compress
  $existing = gh api "repos/$repo/contents/$triggerPath?ref=$branch" 2>$null | ConvertFrom-Json
  if ($LASTEXITCODE -eq 0 -and $existing.sha) { $body = (@{ message = 'chore(copilot): trigger TEST credential restoration'; content = $content; branch = $branch; sha = $existing.sha } | ConvertTo-Json -Compress) }
  $result = $body | gh api "repos/$repo/contents/$triggerPath" --method PUT --input - | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0 -or -not $result.commit.sha) { throw 'No se pudo activar el workflow mediante push controlado.' }
  return $result.commit.sha
}

try {
  gh auth status --hostname github.com *> $null
  if ($LASTEXITCODE -ne 0) { throw 'La sesión local de GitHub CLI no está autenticada.' }
  $passwords[$secretNames[0]] = Read-TemporaryPassword 'jorge.ramos@dori.mx'
  $passwords[$secretNames[1]] = Read-TemporaryPassword 'consola@dori.mx'
  $passwords[$secretNames[2]] = Read-TemporaryPassword 'supervision.pue@dori.mx'
  foreach ($name in $secretNames) { Set-GitHubSecret $name $passwords[$name] }
  $triggerSha = Push-RestoreTrigger
  $runId = $null
  for ($attempt = 0; $attempt -lt 30 -and -not $runId; $attempt++) {
    Start-Sleep -Seconds 2
    $runs = gh run list --repo $repo --workflow $workflow --branch $branch --limit 10 --json databaseId,status,headBranch,headSha,event | ConvertFrom-Json
    $runId = ($runs | Where-Object { $_.headBranch -eq $branch -and $_.headSha -eq $triggerSha -and $_.event -eq 'push' } | Select-Object -First 1).databaseId
  }
  if (-not $runId) { throw 'No se pudo localizar el run de restauración.' }
  gh run watch $runId --repo $repo --exit-status
  if ($LASTEXITCODE -ne 0) { throw "El workflow de restauración terminó con error (run $runId)." }
  Write-Output 'PASS: credenciales TEST actualizadas mediante workflow administrativo.'
} finally {
  foreach ($name in $secretNames) { gh secret delete $name --repo $repo --confirm *> $null }
  foreach ($name in @($passwords.Keys)) { $passwords[$name] = $null }
  $passwords.Clear()
}
