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

try {
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
