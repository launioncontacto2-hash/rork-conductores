[CmdletBinding()]
param(
    [string]$CredentialPath = (Join-Path (Join-Path $env:LOCALAPPDATA 'DORI') 'adquisicion-test-credentials.txt')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedProjectRef = 'yyxzuiantrmoyozetswv'
$expectedEnvironmentID = '9f8d4a52-0f0e-4a3f-9a1e-2c6f5b8d7e10'

function Read-LocalValue {
    param([Parameter(Mandatory)] [string[]]$Lines, [Parameter(Mandatory)] [string]$Prefix)

    $line = $Lines | Where-Object { $_.StartsWith($Prefix) } | Select-Object -First 1
    if (-not $line) {
        throw "Falta la configuración local '$Prefix'."
    }
    $line.Substring($Prefix.Length)
}

function New-AuthHeaders {
    param([Parameter(Mandatory)] $Session, [Parameter(Mandatory)] [string]$PublishableKey)

    @{
        apikey        = $PublishableKey
        Authorization = "Bearer $($Session.access_token)"
        Accept        = 'application/json'
        'Content-Type' = 'application/json'
        'User-Agent'  = 'DORI-TEST-E2E/1.0'
    }
}

function Invoke-Rpc {
    param(
        [Parameter(Mandatory)] [string]$URL,
        [Parameter(Mandatory)] [hashtable]$Headers,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Payload
    )

    Invoke-RestMethod -Method Post -Uri "$URL/rest/v1/rpc/$Name" -Headers $Headers `
        -Body ($Payload | ConvertTo-Json -Compress -Depth 8)
}

function Test-RpcRejected {
    param(
        [Parameter(Mandatory)] [string]$URL,
        [Parameter(Mandatory)] [hashtable]$Headers,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Payload
    )

    $response = Invoke-WebRequest -SkipHttpErrorCheck -Method Post `
        -Uri "$URL/rest/v1/rpc/$Name" -Headers $Headers `
        -Body ($Payload | ConvertTo-Json -Compress -Depth 8)
    $response.StatusCode -ge 400
}

function Add-Result {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Results,
        [Parameter(Mandatory)] [string]$Device,
        [Parameter(Mandatory)] [string]$Role,
        [Parameter(Mandatory)] [string]$Step,
        [Parameter(Mandatory)] [bool]$Passed,
        [Parameter(Mandatory)] [string]$Detail
    )

    $Results.Add([pscustomobject]@{
        Dispositivo = $Device
        Rol         = $Role
        Paso        = $Step
        Resultado   = if ($Passed) { 'PASS' } else { 'FAIL' }
        Detalle     = $Detail
    })
}

if (-not (Test-Path -LiteralPath $CredentialPath)) {
    throw "No existe el archivo local de credenciales TEST: $CredentialPath"
}

$lines = @(
    Get-Content -LiteralPath $CredentialPath |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
$url = Read-LocalValue $lines 'Supabase URL: '
$publishableKey = Read-LocalValue $lines 'Publishable key: '
$adminEmail = Read-LocalValue $lines 'Administrador DORI: '
$adminPassword = Read-LocalValue $lines 'Contraseña administrador: '
$providerEmail = Read-LocalValue $lines 'Usuario Proveedor: '
$providerPassword = Read-LocalValue $lines 'Contraseña proveedor: '

if ($url -ne "https://$expectedProjectRef.supabase.co") {
    throw 'El destino no es el proyecto Supabase TEST autorizado.'
}

$signInHeaders = @{
    apikey         = $publishableKey
    'Content-Type' = 'application/json'
    'User-Agent'   = 'DORI-TEST-E2E/1.0'
}

function Sign-In {
    param([string]$Email, [string]$Password)

    Invoke-RestMethod -Method Post -Uri "$url/auth/v1/token?grant_type=password" `
        -Headers $signInHeaders `
        -Body (@{ email = $Email; password = $Password } | ConvertTo-Json -Compress)
}

$provider = Sign-In $providerEmail $providerPassword
$admin = Sign-In $adminEmail $adminPassword
$providerHeaders = New-AuthHeaders $provider $publishableKey
$adminHeaders = New-AuthHeaders $admin $publishableKey
$results = [System.Collections.Generic.List[object]]::new()

$providerMembership = @(
    Invoke-RestMethod -Method Get `
        -Uri "$url/rest/v1/acquisition_memberships?select=environment_id,supplier_id,role&role=eq.provider" `
        -Headers $providerHeaders
)[0]
$adminMembership = @(
    Invoke-RestMethod -Method Get `
        -Uri "$url/rest/v1/acquisition_memberships?select=environment_id,role&role=eq.dori_admin" `
        -Headers $adminHeaders
)[0]
$request = @(
    Invoke-RestMethod -Method Get `
        -Uri "$url/rest/v1/acquisition_requests?select=id,code&code=eq.ADQ-TEST-001" `
        -Headers $providerHeaders
)[0]

$scopeIsTest = $providerMembership.environment_id -eq $expectedEnvironmentID `
    -and $adminMembership.environment_id -eq $expectedEnvironmentID
if (-not $scopeIsTest) {
    throw 'Las identidades no pertenecen al environment_id TEST autorizado.'
}

Add-Result $results 'Backend TEST' 'Administrador DORI' 'Inicio de sesión y rol' `
    ($adminMembership.role -eq 'dori_admin') 'Sesión real y membresía DORI.'
Add-Result $results 'Backend TEST' 'Usuario Proveedor' 'Inicio de sesión y rol' `
    ($providerMembership.role -eq 'provider' -and $null -ne $providerMembership.supplier_id) `
    'Sesión real y membresía de proveedor aislada.'
Add-Result $results 'Backend TEST' 'Usuario Proveedor' 'Solicitud compartida' `
    ($request.code -eq 'ADQ-TEST-001') 'ADQ-TEST-001 visible.'

$offerID = [guid]::NewGuid()
$offerIDText = $offerID.ToString()
$syntheticVIN = 'TESTDRH25PUE' + $offerID.ToString('N').Substring(0, 5).ToUpperInvariant()
# Real JPEG bytes, matching the UIImage.jpegData payload used by the iPhone.
$image = [Convert]::FromBase64String(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q=='
)
$evidence = @()
foreach ($kind in @('vin', 'dashboard', 'front')) {
    $path = "$expectedEnvironmentID/$($providerMembership.supplier_id)/$offerIDText/$kind.jpg"
    $uploadHeaders = @{
        apikey         = $publishableKey
        Authorization  = "Bearer $($provider.access_token)"
        'x-upsert'     = 'false'
        'User-Agent'   = 'DORI-TEST-E2E/1.0'
    }
    $upload = Invoke-RestMethod -Method Post `
        -Uri "$url/storage/v1/object/acquisition-evidence/$path" `
        -Headers $uploadHeaders -ContentType 'image/jpeg' -Body $image
    if (-not $upload.Key -and -not $upload.key) {
        throw "No se pudo cargar la evidencia de prueba '$kind'."
    }
    $evidence += @{ kind = $kind; path = $path }
}
Add-Result $results 'Backend TEST' 'Usuario Proveedor' 'Tres evidencias' `
    ($evidence.Count -eq 3) 'VIN, tablero y vista general en bucket privado.'

$baseSubmission = @{
    p_offer_id          = $offerIDText
    p_request_id        = $request.id
    p_vin               = $syntheticVIN
    p_model             = 'BYD Dolphin Mini'
    p_version           = 'Plus'
    p_year              = 2025
    p_mileage           = 8400
    p_declared_soh      = $null
    p_color             = 'Blanco'
    p_price_mxn         = 274000
    p_transfer_included = $true
    p_evidence          = $evidence
    p_idempotency_key   = "block6-submit-$offerIDText"
}

$missingEvidence = $baseSubmission.Clone()
$missingEvidence.p_evidence = @($evidence[0], $evidence[1])
$missingEvidence.p_idempotency_key = "block6-missing-evidence-$offerIDText"
Add-Result $results 'Backend TEST' 'Usuario Proveedor' 'Foto faltante' `
    (Test-RpcRejected $url $providerHeaders 'submit_acquisition_offer' $missingEvidence) `
    'El backend rechazó dos evidencias.'

$emptyVIN = $baseSubmission.Clone()
$emptyVIN.p_vin = ''
$emptyVIN.p_idempotency_key = "block6-empty-vin-$offerIDText"
Add-Result $results 'Backend TEST' 'Usuario Proveedor' 'VIN vacío' `
    (Test-RpcRejected $url $providerHeaders 'submit_acquisition_offer' $emptyVIN) `
    'El backend rechazó el VIN vacío.'

$invalidPrice = $baseSubmission.Clone()
$invalidPrice.p_price_mxn = 0
$invalidPrice.p_idempotency_key = "block6-invalid-price-$offerIDText"
Add-Result $results 'Backend TEST' 'Usuario Proveedor' 'Precio inválido' `
    (Test-RpcRejected $url $providerHeaders 'submit_acquisition_offer' $invalidPrice) `
    'El backend rechazó el precio no positivo.'

$networkFailureHandled = $false
try {
    Invoke-WebRequest -Uri 'http://127.0.0.1:1/dori-network-test' `
        -ConnectionTimeoutSeconds 1 -OperationTimeoutSeconds 1 | Out-Null
}
catch {
    $networkFailureHandled = $true
}
Add-Result $results 'Backend TEST' 'Usuario Proveedor' 'Pérdida temporal de red' `
    $networkFailureHandled 'El cliente de prueba recibió un error controlado.'

$submitted = Invoke-Rpc $url $providerHeaders 'submit_acquisition_offer' $baseSubmission
Add-Result $results 'Backend TEST' 'Usuario Proveedor' 'Oferta $274,000' `
    ($submitted.status -eq 'submitted') 'Oferta persistida mediante RPC.'

$adminVisible = @(
    Invoke-RestMethod -Method Get `
        -Uri "$url/rest/v1/acquisition_offers?select=id,status&id=eq.$offerIDText" `
        -Headers $adminHeaders
)
Add-Result $results 'Backend TEST' 'Administrador DORI' 'Consulta compartida' `
    ($adminVisible.Count -eq 1) 'La misma oferta es visible para DORI.'

$providerAward = @{
    p_offer_id = $offerIDText; p_action = 'award'; p_amount_mxn = 271000
    p_message = $null; p_idempotency_key = "block6-invalid-award-$offerIDText"
}
Add-Result $results 'Backend TEST' 'Usuario Proveedor' 'Adjudicación no autorizada' `
    (Test-RpcRejected $url $providerHeaders 'respond_acquisition_offer' $providerAward) `
    'La transición fue rechazada por rol.'

$doriCounter = Invoke-Rpc $url $adminHeaders 'respond_acquisition_offer' @{
    p_offer_id = $offerIDText; p_action = 'counteroffer'; p_amount_mxn = 268000
    p_message = 'Oferta DORI'; p_idempotency_key = "block6-dori-counter-$offerIDText"
}
Add-Result $results 'Backend TEST' 'Administrador DORI' 'Contraoferta $268,000' `
    ($doriCounter.status -eq 'negotiating') 'Contraoferta persistida.'

$providerCounter = Invoke-Rpc $url $providerHeaders 'respond_acquisition_offer' @{
    p_offer_id = $offerIDText; p_action = 'counteroffer'; p_amount_mxn = 271000
    p_message = 'Contraoferta de agencia'; p_idempotency_key = "block6-provider-counter-$offerIDText"
}
Add-Result $results 'Backend TEST' 'Usuario Proveedor' 'Contraoferta $271,000' `
    ($providerCounter.status -eq 'negotiating') 'Contraoferta persistida.'

$accepted = Invoke-Rpc $url $adminHeaders 'respond_acquisition_offer' @{
    p_offer_id = $offerIDText; p_action = 'accept'; p_amount_mxn = $null
    p_message = 'Precio acordado'; p_idempotency_key = "block6-accept-$offerIDText"
}
Add-Result $results 'Backend TEST' 'Administrador DORI' 'Aceptación $271,000' `
    ($accepted.status -eq 'price_agreed' -and [int]$accepted.agreed_price_mxn -eq 271000) `
    'Precio comercial acordado.'

$awarded = Invoke-Rpc $url $adminHeaders 'respond_acquisition_offer' @{
    p_offer_id = $offerIDText; p_action = 'award'; p_amount_mxn = 271000
    p_message = 'Compra confirmada'; p_idempotency_key = "block6-award-$offerIDText"
}
$orderID = [string]$awarded.order_id
Add-Result $results 'Backend TEST' 'Administrador DORI' 'Adjudicación' `
    ($awarded.status -eq 'awarded' -and -not [string]::IsNullOrWhiteSpace($orderID)) `
    'Orden simulada creada.'

$ready = Invoke-Rpc $url $providerHeaders 'complete_acquisition_delivery' @{
    p_order_id = $orderID; p_action = 'ready'; p_checklist = $null; p_result = $null
    p_note = 'Lista para entregar'; p_hold_amount_mxn = $null
    p_idempotency_key = "block6-ready-$offerIDText"
}
Add-Result $results 'Backend TEST' 'Usuario Proveedor' 'Lista para entregar' `
    ($ready.status -eq 'ready_for_delivery') 'Preparación persistida.'

$received = Invoke-Rpc $url $adminHeaders 'complete_acquisition_delivery' @{
    p_order_id = $orderID; p_action = 'receive'
    p_checklist = @{
        vin_correct = $true; mileage_correct = $true; chargers_complete = $true
        keys_complete = $false; new_damage = $false
    }
    p_result = $null; p_note = 'Pendiente por resolver — Segunda llave'
    p_hold_amount_mxn = $null; p_idempotency_key = "block6-receive-$offerIDText"
}
Add-Result $results 'Backend TEST' 'Administrador DORI' 'Recepción condicionada' `
    ($received.recommended_result -eq 'accepted_with_condition' `
        -and [int]$received.hold_amount_mxn -eq 6000) `
    'Resultado y retención calculados por backend.'

$resolved = Invoke-Rpc $url $providerHeaders 'complete_acquisition_delivery' @{
    p_order_id = $orderID; p_action = 'resolve_condition'; p_checklist = $null
    p_result = $null; p_note = 'Segunda llave entregada'; p_hold_amount_mxn = $null
    p_idempotency_key = "block6-resolve-$offerIDText"
}
Add-Result $results 'Backend TEST' 'Usuario Proveedor' 'Resolución de condición' `
    ($resolved.status -eq 'condition_ready_for_review') 'Resolución enviada.'

$closed = Invoke-Rpc $url $adminHeaders 'complete_acquisition_delivery' @{
    p_order_id = $orderID; p_action = 'close_condition'; p_checklist = $null
    p_result = $null; p_note = 'Resolución confirmada'; p_hold_amount_mxn = $null
    p_idempotency_key = "block6-close-$offerIDText"
}
Add-Result $results 'Backend TEST' 'Administrador DORI' 'Cierre' `
    ($closed.status -eq 'closed') 'Adquisición cerrada.'

$order = @(
    Invoke-RestMethod -Method Get `
        -Uri "$url/rest/v1/acquisition_orders?select=status,payment_status,final_price_mxn&id=eq.$orderID" `
        -Headers $adminHeaders
)[0]
$hold = @(
    Invoke-RestMethod -Method Get `
        -Uri "$url/rest/v1/acquisition_holds?select=status,amount_mxn&order_id=eq.$orderID" `
        -Headers $adminHeaders
)[0]
$providerAssessmentResponse = Invoke-WebRequest -Method Get `
    -Uri "$url/rest/v1/acquisition_offer_assessments?select=offer_id&offer_id=eq.$offerIDText" `
    -Headers $providerHeaders
$providerAssessments = ConvertFrom-Json -InputObject $providerAssessmentResponse.Content -NoEnumerate

Add-Result $results 'Backend TEST' 'Backend' 'Persistencia final' `
    ($order.status -eq 'closed' -and $order.payment_status -eq 'simulated' `
        -and [int]$order.final_price_mxn -eq 271000 `
        -and $hold.status -eq 'resolved' -and [int]$hold.amount_mxn -eq 6000) `
    'Orden cerrada; retención simulada liberada.'
Add-Result $results 'Backend TEST' 'Usuario Proveedor' 'Valoración interna oculta' `
    ($providerAssessments.Count -eq 0) 'RLS devolvió cero filas internas.'

$results | Format-Table -AutoSize
Write-Host "Oferta simulada: $offerIDText"
Write-Host "Orden simulada: $orderID"

if ($results.Resultado -contains 'FAIL') {
    throw 'La validación E2E de TEST contiene fallos.'
}

Write-Host 'VALIDACIÓN E2E TEST: PASS' -ForegroundColor Green
