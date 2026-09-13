[CmdletBinding()]
param(
    [string]$CredentialPath = (Join-Path (Join-Path $env:LOCALAPPDATA 'DORI') 'adquisicion-test-credentials.txt'),
    [switch]$DiagnoseOmittedNilArguments
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedURL = 'https://yyxzuiantrmoyozetswv.supabase.co'
$expectedEnvironmentID = '9f8d4a52-0f0e-4a3f-9a1e-2c6f5b8d7e10'
$expectedAdminUID = '8d0fa34d-226c-4dc2-87e5-ec15b7273c79'
$expectedProviderUID = '05cfd8bf-feea-4d3c-afcf-c216d2b2f9f4'
$expectedAdminProfileID = 'ad300000-0000-4000-8000-000000000001'
$expectedProviderProfileID = 'ad300000-0000-4000-8000-000000000002'
$expectedAdminMembershipID = 'ad310000-0000-4000-8000-000000000001'
$expectedProviderMembershipID = 'ad310000-0000-4000-8000-000000000002'
$expectedSupplierID = '77d64394-9aec-4311-8026-5f452ddd6a52'

function Read-Value {
    param([string[]]$Lines, [string]$Prefix)
    $line = $Lines | Where-Object { $_.StartsWith($Prefix) } | Select-Object -First 1
    if (-not $line) { throw "Falta la configuración local '$Prefix'." }
    $line.Substring($Prefix.Length)
}

function New-Headers {
    param($Session, [string]$Key)
    @{
        apikey = $Key
        Authorization = "Bearer $($Session.access_token)"
        Accept = 'application/json'
        'Content-Type' = 'application/json'
        'User-Agent' = 'DORI-UNIT-CHAT-TEST/1.0'
    }
}

function Invoke-Rpc {
    param([string]$URL, [hashtable]$Headers, [string]$Name, [hashtable]$Body)
    Invoke-RestMethod -Method Post -Uri "$URL/rest/v1/rpc/$Name" -Headers $Headers `
        -Body ($Body | ConvertTo-Json -Compress -Depth 6)
}

if (-not (Test-Path -LiteralPath $CredentialPath)) {
    throw "No existe el archivo local de credenciales TEST."
}

$lines = @(Get-Content -LiteralPath $CredentialPath | Where-Object { $_.Trim().Length -gt 0 })
$url = Read-Value $lines 'Supabase URL: '
$key = Read-Value $lines 'Publishable key: '
$adminEmail = Read-Value $lines 'Administrador DORI: '
$adminPassword = Read-Value $lines 'Contraseña administrador: '
$providerEmail = Read-Value $lines 'Usuario Proveedor: '
$providerPassword = Read-Value $lines 'Contraseña proveedor: '
if ($url -ne $expectedURL) { throw 'El destino no es Supabase TEST autorizado.' }

$signInHeaders = @{ apikey = $key; 'Content-Type' = 'application/json' }
function Sign-In([string]$Email, [string]$Password) {
    Invoke-RestMethod -Method Post -Uri "$url/auth/v1/token?grant_type=password" `
        -Headers $signInHeaders -Body (@{ email = $Email; password = $Password } | ConvertTo-Json -Compress)
}

$adminSession = Sign-In $adminEmail $adminPassword
$providerSession = Sign-In $providerEmail $providerPassword
if ($adminSession.user.id -ne $expectedAdminUID -or $providerSession.user.id -ne $expectedProviderUID) {
    throw 'El cambio de correo alteró una identidad Auth TEST.'
}
$adminHeaders = New-Headers $adminSession $key
$providerHeaders = New-Headers $providerSession $key

$adminProfile = @(Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/profiles?select=id,environment_id,status&auth_user_id=eq.$($adminSession.user.id)" `
    -Headers $adminHeaders)
if ($adminProfile.Count -ne 1 -or $adminProfile[0].id -ne $expectedAdminProfileID -or `
    $adminProfile[0].status -ne 'active' -or $adminProfile[0].environment_id -ne $expectedEnvironmentID) {
    throw 'La cuenta DORI no resolvió su perfil TEST original.'
}

$adminMembership = @(Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/acquisition_memberships?select=id,profile_id,environment_id,supplier_id,role,status&profile_id=eq.$($adminProfile[0].id)" `
    -Headers $adminHeaders)
if ($adminMembership.Count -ne 1 -or $adminMembership[0].id -ne $expectedAdminMembershipID -or `
    $adminMembership[0].role -ne 'dori_admin' -or $adminMembership[0].supplier_id -or `
    $adminMembership[0].status -ne 'active' -or $adminMembership[0].environment_id -ne $expectedEnvironmentID) {
    throw 'La cuenta DORI no resolvió su membresía TEST original.'
}

$providerProfile = @(Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/profiles?select=id,environment_id,status&auth_user_id=eq.$($providerSession.user.id)" `
    -Headers $providerHeaders)
if ($providerProfile.Count -ne 1 -or $providerProfile[0].id -ne $expectedProviderProfileID -or `
    $providerProfile[0].status -ne 'active' -or $providerProfile[0].environment_id -ne $expectedEnvironmentID) {
    throw 'La cuenta proveedor no resolvió un perfil activo.'
}

$membership = @(Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/acquisition_memberships?select=id,profile_id,environment_id,supplier_id,role,status&profile_id=eq.$($providerProfile[0].id)" `
    -Headers $providerHeaders)
if ($membership.Count -ne 1 -or $membership[0].id -ne $expectedProviderMembershipID -or `
    $membership[0].supplier_id -ne $expectedSupplierID -or $membership[0].role -ne 'provider' -or `
    $membership[0].status -ne 'active' -or $membership[0].environment_id -ne $expectedEnvironmentID) {
    throw 'La cuenta proveedor no resolvió su membresía TEST activa.'
}

$supplier = @(Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/acquisition_suppliers?select=id,name,status&id=eq.$($membership[0].supplier_id)" `
    -Headers $providerHeaders)
if ($supplier.Count -ne 1 -or $supplier[0].status -ne 'active') {
    throw 'La membresía proveedor no resolvió un proveedor activo.'
}

$requests = @(Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/acquisition_requests?select=id,code&code=eq.ADQ-TEST-001" `
    -Headers $providerHeaders)
$offers = @(Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/acquisition_offers?select=id,vin,supplier_id&order=submitted_at.desc&limit=1" `
    -Headers $providerHeaders)
if ($requests.Count -ne 1 -or $offers.Count -ne 1) {
    throw 'El dashboard proveedor no pudo reconstruir solicitud y unidad.'
}

$providerContacts = Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/acquisition_contacts?select=supplier_id,email&order=supplier_id.asc.nullsfirst" `
    -Headers $providerHeaders
$adminContacts = Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/acquisition_contacts?select=supplier_id,email&order=supplier_id.asc.nullsfirst" `
    -Headers $adminHeaders
if ($providerContacts.Count -ne 2 -or $adminContacts.Count -lt 2) {
    $providerEmails = @($providerContacts | ForEach-Object { $_.email }) -join ', '
    $adminEmails = @($adminContacts | ForEach-Object { $_.email }) -join ', '
    throw "El directorio institucional no respetó el alcance esperado (proveedor=$($providerContacts.Count): $providerEmails; DORI=$($adminContacts.Count): $adminEmails)."
}
if (-not ($providerContacts.email -contains 'adquisiciones.pue@dori.mx') -or `
    -not ($providerContacts.email -contains 'byd.iztacalco@dori.mx')) {
    throw 'El directorio TEST no contiene los correos institucionales aprobados.'
}

$offerID = [string]$offers[0].id
$supplierID = [string]$membership[0].supplier_id
$adminThread = Invoke-Rpc $url $adminHeaders 'ensure_acquisition_chat_thread' @{
    p_supplier_id = $null; p_offer_id = $offerID
}
$providerThread = Invoke-Rpc $url $providerHeaders 'ensure_acquisition_chat_thread' @{
    p_supplier_id = $supplierID; p_offer_id = $offerID
}
if ($adminThread.id -ne $providerThread.id -or $adminThread.scope -ne 'unit') {
    throw 'Administrador y proveedor no resolvieron la misma conversación de unidad.'
}

if ($DiagnoseOmittedNilArguments) {
    # Build 1031 used synthesized Encodable conformance. Swift omits nil optionals,
    # so this is the exact text-only JSON shape produced by that binary.
    $legacyPayload = @{
        p_thread_id = [string]$providerThread.id
        p_body = 'Diagnóstico sin persistir'
        p_idempotency_key = "diagnostic-omitted-nil-$([guid]::NewGuid().ToString('N'))"
    }
    $legacyResponse = Invoke-WebRequest -SkipHttpErrorCheck -Method Post `
        -Uri "$url/rest/v1/rpc/send_acquisition_chat_message" -Headers $providerHeaders `
        -Body ($legacyPayload | ConvertTo-Json -Compress)
    if ($legacyResponse.StatusCode -lt 400) {
        throw 'La forma incompleta de build 1031 fue aceptada inesperadamente.'
    }
    $failure = $legacyResponse.Content | ConvertFrom-Json
    [pscustomobject]@{
        'RPC' = 'send_acquisition_chat_message'
        'HTTP status' = $legacyResponse.StatusCode
        'Código' = $failure.code
        'Mensaje' = $failure.message
        'Details' = $failure.details
        'Hint' = $failure.hint
        'Thread' = "…$(([string]$providerThread.id).Substring(28))"
        'Scope' = $providerThread.scope
        'Rol' = 'provider'
    } | Format-List
}

$marker = [guid]::NewGuid().ToString('N').Substring(0, 8)
$adminBody = "Prueba DORI unidad $marker"
$providerBody = "Respuesta proveedor unidad $marker"
$null = Invoke-Rpc $url $adminHeaders 'send_acquisition_chat_message' @{
    p_thread_id = [string]$adminThread.id; p_body = $adminBody; p_attachment_path = $null
    p_attachment_mime_type = $null; p_attachment_filename = $null; p_attachment_size_bytes = $null
    p_idempotency_key = "test-unit-chat-admin-$marker"
}
$seenByProvider = @(Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/acquisition_chat_messages?select=id,body&thread_id=eq.$($adminThread.id)&body=eq.$([uri]::EscapeDataString($adminBody))" `
    -Headers $providerHeaders)
if ($seenByProvider.Count -ne 1) { throw 'El proveedor no recibió el mensaje DORI.' }

$null = Invoke-Rpc $url $providerHeaders 'send_acquisition_chat_message' @{
    p_thread_id = [string]$providerThread.id; p_body = $providerBody; p_attachment_path = $null
    p_attachment_mime_type = $null; p_attachment_filename = $null; p_attachment_size_bytes = $null
    p_idempotency_key = "test-unit-chat-provider-$marker"
}
$seenByAdmin = @(Invoke-RestMethod -Method Get `
    -Uri "$url/rest/v1/acquisition_chat_messages?select=id,body&thread_id=eq.$($providerThread.id)&body=eq.$([uri]::EscapeDataString($providerBody))" `
    -Headers $adminHeaders)
if ($seenByAdmin.Count -ne 1) { throw 'DORI no recibió el mensaje del proveedor.' }

[pscustomobject]@{
    'Auth Administrador' = 'PASS'
    'Auth proveedor' = 'PASS'
    'UID sin cambios' = 'PASS'
    'Profiles sin cambios' = 'PASS'
    'Membresías sin cambios' = 'PASS'
    'Proveedor' = 'PASS'
    'Dashboard' = 'PASS'
    'Directorio institucional' = 'PASS'
    'Conversación por unidad compartida' = 'PASS'
    'Mensaje DORI a proveedor' = 'PASS'
    'Mensaje proveedor a DORI' = 'PASS'
} | Format-List
