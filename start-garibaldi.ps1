$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$backendRoot = Join-Path $projectRoot 'backend'
$backendPython = Join-Path $backendRoot '.venv\Scripts\python.exe'
$backendLog = Join-Path $backendRoot 'runtime-api.log'
$backendErrorLog = Join-Path $backendRoot 'runtime-api-error.log'
$healthUrl = 'http://127.0.0.1:8000/health'
$googleCertificatesUrl = 'https://www.googleapis.com/oauth2/v1/certs'

function Test-BackendHealth {
    try {
        $response = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 3
        return $response.status -eq 'ok'
    }
    catch {
        return $false
    }
}

Write-Host 'Comprobando acceso a Google...'
try {
    $googleResponse = Invoke-WebRequest -Uri $googleCertificatesUrl -TimeoutSec 10 -UseBasicParsing
    if ($googleResponse.StatusCode -ne 200) {
        throw "Google respondio con HTTP $($googleResponse.StatusCode)"
    }
}
catch {
    Write-Error "No se puede iniciar Garibaldi: Windows no logra consultar los certificados de Google. $($_.Exception.Message)"
    exit 1
}

if (-not (Test-Path -LiteralPath $backendPython)) {
    Write-Error "No existe el entorno virtual del backend: $backendPython"
    exit 1
}

if (-not (Test-BackendHealth)) {
    Write-Host 'Aplicando migraciones de base de datos...'
    Push-Location $backendRoot
    try {
        & $backendPython -m alembic upgrade head
        if ($LASTEXITCODE -ne 0) {
            throw 'Alembic no pudo actualizar la base de datos.'
        }
    }
    finally {
        Pop-Location
    }

    Write-Host 'Iniciando backend de Garibaldi...'
    Start-Process `
        -FilePath $backendPython `
        -ArgumentList '-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8000', '--proxy-headers', '--forwarded-allow-ips', '127.0.0.1' `
        -WorkingDirectory $backendRoot `
        -RedirectStandardOutput $backendLog `
        -RedirectStandardError $backendErrorLog `
        -WindowStyle Hidden | Out-Null

    $backendReady = $false
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        Start-Sleep -Milliseconds 500
        if (Test-BackendHealth) {
            $backendReady = $true
            break
        }
    }

    if (-not $backendReady) {
        Write-Error "El backend no inicio. Revisa $backendErrorLog"
        exit 1
    }
}

Write-Host 'Backend activo y Google disponible.' -ForegroundColor Green

$adb = Join-Path $env:LOCALAPPDATA 'Android\sdk\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb)) {
    Write-Warning 'El backend quedo activo, pero no encontre Android SDK para abrir la app.'
    exit 0
}

$devices = & $adb devices
$androidDevice = $devices |
    Select-String -Pattern '^\S+\s+device$' |
    Sort-Object { if ($_.Line -match '^emulator-') { 1 } else { 0 } } |
    Select-Object -First 1
if (-not $androidDevice) {
    Write-Warning 'Backend listo. Abre Garibaldi manualmente cuando conectes un telefono o enciendas el emulador.'
    Write-Warning 'El lanzador no inicia emuladores porque QEMU es inestable en esta PC.'
    exit 0
}

$deviceSerial = ($androidDevice.Line -split '\s+')[0]
$deviceKind = if ($deviceSerial -match '^emulator-') { 'emulador' } else { 'telefono' }
Write-Host "Abriendo Garibaldi en el $deviceKind $deviceSerial..."
& $adb -s $deviceSerial shell monkey -p mx.balam.app -c android.intent.category.LAUNCHER 1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "El backend esta activo, pero ADB no pudo abrir la app en el $deviceKind."
    exit 1
}

Write-Host 'Garibaldi esta listo.' -ForegroundColor Green
