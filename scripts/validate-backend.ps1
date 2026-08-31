[CmdletBinding()]
param(
    [switch]$IncludeDryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$allowedBranches = @('main', '15C-backend-test', '15D-backend-shifts')

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory)] [string]$Command,
        [Parameter()] [string[]]$Arguments = @()
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo el comando: $Command $($Arguments -join ' ') (codigo $LASTEXITCODE)."
    }
}

try {
    Set-Location $repoRoot

    Write-Step 'Verificando repositorio y rama'
    if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
        throw "No se encontro un repositorio Git en $repoRoot."
    }

    $branch = (& git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw 'No se pudo consultar la rama actual.'
    }
    if ($branch -notin $allowedBranches) {
        throw "Rama no permitida: '$branch'. Permitidas: $($allowedBranches -join ', ')."
    }
    Write-Host "Rama: $branch" -ForegroundColor Green

    Write-Step 'Verificando Docker'
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker no esta disponible. Abre Docker Desktop y vuelve a ejecutar el script.'
    }
    Invoke-Checked docker @('version', '--format', 'Docker Engine {{.Server.Version}}')

    Write-Step 'Verificando Supabase CLI'
    if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) {
        throw 'Supabase CLI no esta disponible en PATH.'
    }
    Invoke-Checked supabase @('--version')

    Write-Step 'Verificando Supabase local'
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Un estado detenido es una condicion esperada; no debe convertirse en
        # una excepcion antes de que podamos iniciar los servicios locales.
        $ErrorActionPreference = 'Continue'
        & supabase status 1>$null 2>$null
        $statusExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($statusExitCode -ne 0) {
        Write-Host 'Supabase local no esta activo; iniciandolo...' -ForegroundColor Yellow
        Invoke-Checked supabase @('start')
    }

    Write-Step 'Reconstruyendo la base local desde migraciones'
    Invoke-Checked supabase @('db', 'reset', '--local')

    Write-Step 'Ejecutando lint de la base local'
    Invoke-Checked supabase @('db', 'lint', '--local')

    Write-Step 'Ejecutando asesores de seguridad de Supabase'
    Invoke-Checked supabase @(
        'db', 'advisors', '--local', '--type', 'security',
        '--level', 'warn', '--fail-on', 'error'
    )

    Write-Step 'Verificando formato del diff de Git'
    Invoke-Checked git @('diff', '--check')

    $testsPath = Join-Path $repoRoot 'supabase\tests'
    $sqlTests = @(Get-ChildItem -Path $testsPath -Filter '*.sql' -File -ErrorAction SilentlyContinue)
    if ($sqlTests.Count -gt 0) {
        Write-Step "Ejecutando $($sqlTests.Count) prueba(s) SQL"
        Invoke-Checked supabase @('test', 'db')
    }
    else {
        Write-Step 'Pruebas SQL'
        Write-Host 'No hay archivos .sql en supabase/tests; se omite este paso.' -ForegroundColor Yellow
    }

    if ($IncludeDryRun) {
        Write-Step 'Comprobando db push en modo dry-run (sin aplicar cambios)'
        Invoke-Checked supabase @('db', 'push', '--dry-run')
    }
    else {
        Write-Step 'Dry-run remoto omitido'
        Write-Host 'Para incluirlo, ejecuta: .\scripts\validate-backend.ps1 -IncludeDryRun' -ForegroundColor DarkGray
    }

    Write-Host "`nVALIDACION COMPLETADA: PASS" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "`nVALIDACION DETENIDA: FAIL" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {
    Set-Location $repoRoot
}
