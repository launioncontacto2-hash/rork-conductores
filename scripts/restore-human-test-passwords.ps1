$ErrorActionPreference = 'Stop'

$projectRef = 'yyxzuiantrmoyozetswv'
$baseUrl = "https://$projectRef.supabase.co"
$serviceRole = [Environment]::GetEnvironmentVariable('SUPABASE_SERVICE_ROLE_KEY_TEST', 'Process')
if ([string]::IsNullOrWhiteSpace($serviceRole)) {
  throw 'SUPABASE_SERVICE_ROLE_KEY_TEST debe estar disponible sólo en el entorno local del proceso.'
}

$emails = @(
  'jorge.ramos@dori.mx',
  'consola@dori.mx',
  'supervision.pue@dori.mx'
)
$passwords = @{}
$plainValues = New-Object System.Collections.Generic.List[string]

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

try {
  $headers = @{ apikey = $serviceRole; Authorization = "Bearer $serviceRole" }
  $users = @()
  $page = 1
  do {
    $batch = Invoke-RestMethod -Method Get -Uri "$baseUrl/auth/v1/admin/users?page=$page&per_page=100" -Headers $headers
    $users += @($batch.users)
    $page++
  } while ($batch.users.Count -eq 100)

  foreach ($email in $emails) {
    $user = @($users | Where-Object { $_.email -eq $email }) | Select-Object -First 1
    if (-not $user) { throw "No se encontró la identidad TEST: $email" }
    $passwords[$user.id] = Read-TemporaryPassword $email
    $plainValues.Add($passwords[$user.id])
  }

  foreach ($email in $emails) {
    $user = @($users | Where-Object { $_.email -eq $email }) | Select-Object -First 1
    $body = @{ password = $passwords[$user.id]; email_confirm = $true } | ConvertTo-Json
    Invoke-RestMethod -Method Patch -Uri "$baseUrl/auth/v1/admin/users/$($user.id)" -Headers ($headers + @{ 'Content-Type' = 'application/json' }) -Body $body | Out-Null
  }
  Write-Output 'PASS: credenciales TEST actualizadas mediante Admin Auth.'
} finally {
  foreach ($key in @($passwords.Keys)) { $passwords[$key] = $null }
  $plainValues.Clear()
  $serviceRole = $null
  [Environment]::SetEnvironmentVariable('SUPABASE_SERVICE_ROLE_KEY_TEST', $null, 'Process')
}
