$ErrorActionPreference = 'Stop'

$repo = 'launioncontacto2-hash/rork-conductores'
$branch = 'feat/copilot-cross-test-foundation'
$workflow = 'copilot-restore-human-test-passwords.yml'
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

try {
  gh auth status --hostname github.com *> $null
  if ($LASTEXITCODE -ne 0) { throw 'La sesión local de GitHub CLI no está autenticada.' }
  $passwords[$secretNames[0]] = Read-TemporaryPassword 'jorge.ramos@dori.mx'
  $passwords[$secretNames[1]] = Read-TemporaryPassword 'consola@dori.mx'
  $passwords[$secretNames[2]] = Read-TemporaryPassword 'supervision.pue@dori.mx'
  foreach ($name in $secretNames) { Set-GitHubSecret $name $passwords[$name] }
  gh workflow run $workflow --repo $repo --ref $branch
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo iniciar el workflow de restauración.' }
  $runId = $null
  for ($attempt = 0; $attempt -lt 30 -and -not $runId; $attempt++) {
    Start-Sleep -Seconds 2
    $runs = gh run list --repo $repo --workflow $workflow --branch $branch --limit 5 --json databaseId,status,headBranch | ConvertFrom-Json
    $runId = ($runs | Where-Object { $_.headBranch -eq $branch -and ($_.status -eq 'queued' -or $_.status -eq 'in_progress') } | Select-Object -First 1).databaseId
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
