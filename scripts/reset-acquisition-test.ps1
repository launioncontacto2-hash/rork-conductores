[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('LIMPIAR TEST')]
    [string]$Confirmation,
    [string]$CredentialPath = (Join-Path (Join-Path $env:LOCALAPPDATA 'DORI') 'adquisicion-test-credentials.txt'),
    [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedURL = 'https://yyxzuiantrmoyozetswv.supabase.co'
$expectedEnvironmentID = '9f8d4a52-0f0e-4a3f-9a1e-2c6f5b8d7e10'
$allowedBuckets = @('acquisition-evidence', 'acquisition-chat-attachments')

function Read-LocalValue {
    param([string[]]$Lines, [string]$Prefix)
    $line = $Lines | Where-Object { $_.StartsWith($Prefix) } | Select-Object -First 1
    if (-not $line) { throw "Falta la configuración local '$Prefix'." }
    $line.Substring($Prefix.Length)
}

function Sign-In {
    param([string]$URL, [string]$Key, [string]$Email, [string]$Password)
    Invoke-RestMethod -Method Post -Uri "$URL/auth/v1/token?grant_type=password" -Headers @{
        apikey = $Key
        'Content-Type' = 'application/json'
    } -Body (@{ email = $Email; password = $Password } | ConvertTo-Json -Compress)
}

function New-AuthHeaders {
    param($Session, [string]$Key)
    @{
        apikey = $Key
        Authorization = "Bearer $($Session.access_token)"
        Accept = 'application/json'
        'Content-Type' = 'application/json'
        'User-Agent' = 'DORI-TEST-RESET/1.0'
    }
}

function Invoke-Rpc {
    param([string]$URL, [hashtable]$Headers, [string]$Name, [hashtable]$Body)
    Invoke-RestMethod -Method Post -Uri "$URL/rest/v1/rpc/$Name" -Headers $Headers `
        -Body ($Body | ConvertTo-Json -Compress -Depth 8)
}

function Remove-PlannedStorageObjects {
    param(
        [string]$URL,
        [hashtable]$Headers,
        $Plan,
        [string[]]$Buckets
    )

    foreach ($bucket in $Buckets) {
        $paths = @($Plan.storage_objects | Where-Object { $_.bucket -eq $bucket } | ForEach-Object { $_.path })
        for ($offset = 0; $offset -lt $paths.Count; $offset += 100) {
            $end = [Math]::Min($offset + 99, $paths.Count - 1)
            $batch = @($paths[$offset..$end])
            Invoke-RestMethod -Method Delete -Uri "$URL/storage/v1/object/$bucket" -Headers $Headers `
                -Body (@{ prefixes = $batch } | ConvertTo-Json -Compress) | Out-Null
        }
    }
}

if (-not (Test-Path -LiteralPath $CredentialPath)) {
    throw 'No existe el archivo local de credenciales TEST.'
}

$lines = @(Get-Content -LiteralPath $CredentialPath | Where-Object { $_.Trim().Length -gt 0 })
$url = Read-LocalValue $lines 'Supabase URL: '
$key = Read-LocalValue $lines 'Publishable key: '
$adminEmail = Read-LocalValue $lines 'Administrador DORI: '
$adminPassword = Read-LocalValue $lines 'Contraseña administrador: '
$providerEmail = Read-LocalValue $lines 'Usuario Proveedor: '
$providerPassword = Read-LocalValue $lines 'Contraseña proveedor: '

if ($url -ne $expectedURL) { throw 'El destino no es el Supabase TEST autorizado.' }
if ($key -notlike 'sb_publishable_*') { throw 'La configuración no contiene una publishable key TEST.' }

$admin = Sign-In $url $key $adminEmail $adminPassword
$provider = Sign-In $url $key $providerEmail $providerPassword
$adminHeaders = New-AuthHeaders $admin $key
$providerHeaders = New-AuthHeaders $provider $key

$adminProfile = @(Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/profiles?select=id,environment_id,status&auth_user_id=eq.$($admin.user.id)" `
    -Headers $adminHeaders)
$providerProfile = @(Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/profiles?select=id,environment_id,status&auth_user_id=eq.$($provider.user.id)" `
    -Headers $providerHeaders)
if ($adminProfile.Count -ne 1 -or $adminProfile[0].environment_id -ne $expectedEnvironmentID -or `
    $adminProfile[0].status -ne 'active') { throw 'La identidad administradora no conserva un perfil activo en TEST.' }
if ($providerProfile.Count -ne 1 -or $providerProfile[0].environment_id -ne $expectedEnvironmentID -or `
    $providerProfile[0].status -ne 'active') { throw 'La identidad proveedor no conserva un perfil activo en TEST.' }

$adminMembership = @(Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/acquisition_memberships?select=environment_id,role,status&profile_id=eq.$($adminProfile[0].id)" `
    -Headers $adminHeaders)
$providerMembership = @(Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/acquisition_memberships?select=environment_id,supplier_id,role,status&profile_id=eq.$($providerProfile[0].id)" `
    -Headers $providerHeaders)

if ($adminMembership.Count -ne 1 -or $adminMembership[0].environment_id -ne $expectedEnvironmentID -or `
    $adminMembership[0].role -ne 'dori_admin' -or $adminMembership[0].status -ne 'active') {
    throw 'La identidad administradora no conserva una membresía DORI activa en TEST.'
}
if ($providerMembership.Count -ne 1 -or $providerMembership[0].environment_id -ne $expectedEnvironmentID -or `
    $providerMembership[0].role -ne 'provider' -or $providerMembership[0].status -ne 'active' -or `
    -not $providerMembership[0].supplier_id) {
    throw 'La identidad proveedor no conserva una membresía activa y proveedor asignado en TEST.'
}

$plan = Invoke-Rpc $url $adminHeaders 'plan_test_acquisition_environment_reset' @{
    p_confirmation = $Confirmation
}
if ($plan.environment_id -ne $expectedEnvironmentID) { throw 'El plan pertenece a otro environment.' }

foreach ($object in @($plan.storage_objects)) {
    if ($object.bucket -notin $allowedBuckets) { throw 'El plan incluyó un bucket no autorizado.' }
    if (-not $object.path.StartsWith("$expectedEnvironmentID/")) { throw 'El plan incluyó una ruta fuera de TEST.' }
}

Write-Output 'Conteos antes de limpiar TEST:'
$plan.counts | ConvertTo-Json -Compress
$plan.storage_objects |
    Group-Object bucket |
    ForEach-Object { Write-Output "Objetos planeados en $($_.Name): $($_.Count)" }
if ($PlanOnly) { return }

Remove-PlannedStorageObjects $url $adminHeaders $plan $allowedBuckets

# Storage puede completar una eliminación masiva parcialmente sin devolver un
# error de transporte. Reconsultamos la fuente autoritativa y repetimos solo
# la allowlist restante antes de permitir que el RPC borre filas.
for ($attempt = 1; $attempt -le 4; $attempt++) {
    $remainingPlan = Invoke-Rpc $url $adminHeaders 'plan_test_acquisition_environment_reset' @{
        p_confirmation = $Confirmation
    }
    if (@($remainingPlan.storage_objects).Count -eq 0) { break }
    Remove-PlannedStorageObjects $url $adminHeaders $remainingPlan $allowedBuckets
}
$remainingPlan = Invoke-Rpc $url $adminHeaders 'plan_test_acquisition_environment_reset' @{
    p_confirmation = $Confirmation
}
if (@($remainingPlan.storage_objects).Count -ne 0) {
    throw "Storage TEST no quedó vacío tras reintentos verificados: $(@($remainingPlan.storage_objects).Count) objetos."
}

$result = Invoke-Rpc $url $adminHeaders 'reset_test_acquisition_environment' @{
    p_confirmation = $Confirmation
}
$verification = Invoke-Rpc $url $adminHeaders 'plan_test_acquisition_environment_reset' @{
    p_confirmation = $Confirmation
}

$remaining = @($verification.counts.PSObject.Properties | Where-Object { [int64]$_.Value -ne 0 })
if ($remaining.Count -ne 0 -or @($verification.storage_objects).Count -ne 0) {
    throw "La comprobación final encontró datos transaccionales u objetos pendientes: $($remaining.Name -join ', ')."
}

# Una autenticación posterior comprueba que el reset no eliminó identidades.
$adminAfter = Sign-In $url $key $adminEmail $adminPassword
$providerAfter = Sign-In $url $key $providerEmail $providerPassword
if ($adminAfter.user.id -ne $admin.user.id -or $providerAfter.user.id -ne $provider.user.id) {
    throw 'La identidad de una cuenta TEST cambió durante la limpieza.'
}

Write-Output 'Conteos después de limpiar TEST:'
$verification.counts | ConvertTo-Json -Compress
Write-Output "Login DORI: PASS (UID $($adminAfter.user.id))"
Write-Output "Login Proveedor: PASS (UID $($providerAfter.user.id))"
Write-Output "Objetos Storage eliminados: $(@($plan.storage_objects).Count)"
Write-Output 'Limpieza transaccional TEST: PASS'
