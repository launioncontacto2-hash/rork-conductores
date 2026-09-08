[CmdletBinding()]
param(
    [switch]$IncludeDryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$webRoot = Join-Path $repoRoot 'web'

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory)] [string]$Command,
        [Parameter()] [string[]]$Arguments = @(),
        [Parameter()] [string]$WorkingDirectory = $repoRoot
    )

    Push-Location $WorkingDirectory
    try {
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Fallo el comando: $Command $($Arguments -join ' ') (codigo $LASTEXITCODE)."
        }
    }
    finally {
        Pop-Location
    }
}

function Assert-NoTrackedSecrets {
    $gitArguments = @('-C', $repoRoot, '-c', "safe.directory=$repoRoot")
    $forbiddenCredentials = @(
        ('Kymyly' + '14'),
        ('Direccion' + '14'),
        ('Gerencia' + '14'),
        ('Supervisor' + '14'),
        ('Taller' + '14'),
        ('Reclutamiento' + '14'),
        ('Laboratorio' + '14'),
        ('Prueba' + '14')
    )

    foreach ($credential in $forbiddenCredentials) {
        $null = & git @gitArguments grep '-l' '-F' '--' $credential
        if ($LASTEXITCODE -eq 0) {
            throw 'El repositorio volvió a incluir una credencial de demostración retirada.'
        }
        if ($LASTEXITCODE -gt 1) {
            throw 'No fue posible completar la revisión de credenciales incrustadas.'
        }
    }

    $secretPatterns = @(
        'sb_secret_[A-Za-z0-9_-]+',
        '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    )
    foreach ($pattern in $secretPatterns) {
        $null = & git @gitArguments grep '-l' '-E' '--' $pattern
        if ($LASTEXITCODE -eq 0) {
            throw 'El repositorio contiene material secreto o una llave privada.'
        }
        if ($LASTEXITCODE -gt 1) {
            throw 'No fue posible completar la revisión de secretos.'
        }
    }

    $trackedFiles = @(& git @gitArguments ls-files)
    if ($LASTEXITCODE -ne 0) {
        throw 'No fue posible revisar los archivos rastreados por Git.'
    }
    $sensitiveFiles = @(
        $trackedFiles | Where-Object {
            $leaf = Split-Path -Leaf $_
            $leaf -eq '.env' -or
            $leaf -match '\.(pem|p12|pfx|key)$'
        }
    )
    if ($sensitiveFiles.Count -gt 0) {
        throw 'Git rastrea un archivo de entorno, certificado o llave privada.'
    }
}

function Assert-NoDirectBackendWrites {
    $gitArguments = @('-C', $repoRoot, '-c', "safe.directory=$repoRoot")
    $runtimeRoots = @(
        'ios-turno-ev/TurnoEV',
        'android/app/src/main',
        'web/src'
    )
    $runtimeFiles = @(
        & git @gitArguments ls-files '--' @runtimeRoots |
            Where-Object { $_ -match '\.(swift|kt|kts|js|jsx|ts|tsx)$' }
    )
    if ($LASTEXITCODE -ne 0) {
        throw 'No fue posible enumerar el código de las aplicaciones.'
    }

    $directWritePattern = '(?s)\.from\s*\([^\)]*\)\s*\.(insert|update|upsert|delete)\s*\('
    foreach ($relativePath in $runtimeFiles) {
        $absolutePath = Join-Path $repoRoot $relativePath
        $source = Get-Content -LiteralPath $absolutePath -Raw
        if ($source -match $directWritePattern) {
            throw "La aplicación intenta escribir directamente en una tabla: $relativePath. Usa un RPC transaccional y auditado."
        }
    }
}

try {
    Write-Step 'Comprobando que Git no contenga credenciales ni secretos'
    Assert-NoTrackedSecrets

    Write-Step 'Comprobando que las aplicaciones no escriban directamente en tablas'
    Assert-NoDirectBackendWrites

    Write-Step 'Validando Supabase local, seguridad y pruebas SQL'
    $backendArguments = @()
    if ($IncludeDryRun) { $backendArguments += '-IncludeDryRun' }
    $validationArguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'validate-backend.ps1')
    ) + $backendArguments
    Invoke-Checked -Command powershell -Arguments $validationArguments

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw 'Node.js y npm son necesarios para validar Consola DORI.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $webRoot 'node_modules'))) {
        throw 'Faltan las dependencias web. Ejecuta npm install dentro de web antes de validar.'
    }

    Write-Step 'Revisando Consola DORI'
    Invoke-Checked -Command npm -Arguments @('run', 'lint') -WorkingDirectory $webRoot
    Invoke-Checked -Command npm -Arguments @('run', 'test:unit') -WorkingDirectory $webRoot

    $localPlaywright = Join-Path $repoRoot '.codex-tmp-playwright'
    $previousPlaywrightPath = $env:PLAYWRIGHT_BROWSERS_PATH
    try {
        if (Test-Path -LiteralPath $localPlaywright) {
            $env:PLAYWRIGHT_BROWSERS_PATH = $localPlaywright
        }
        Invoke-Checked -Command npm -Arguments @('run', 'test:browser:run') -WorkingDirectory $webRoot
    }
    finally {
        $env:PLAYWRIGHT_BROWSERS_PATH = $previousPlaywrightPath
    }

    Invoke-Checked -Command npm -Arguments @('run', 'build') -WorkingDirectory $webRoot

    Write-Step 'Comprobando higiene del repositorio'
    Invoke-Checked -Command git -Arguments @('-c', "safe.directory=$repoRoot", 'diff', '--check') -WorkingDirectory $repoRoot

    Write-Host "`nVALIDACION INTEGRAL DORI: PASS" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "`nVALIDACION INTEGRAL DORI: FAIL" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {
    Set-Location $repoRoot
}
