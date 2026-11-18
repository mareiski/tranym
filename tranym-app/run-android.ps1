# This script builds the Photon static assets for the mobile app, 
# copies the dist to the app's assets directory, and runs the app on android.

param(
  [string]$BackendUrl = "http://10.0.2.2:1236",
  [string]$InstanceUrl = ""
)

# cancel on any error
$ErrorActionPreference = "Stop"

# Load all variables from .env file
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    $envContent = Get-Content $envFile -Raw
    $lines = $envContent -split "`r?`n"
    foreach ($line in $lines) {
        $line = $line.Trim()
        if ($line -and $line -notmatch '^[#;]') {
            $parts = $line -split '=', 2
            if ($parts.Count -eq 2) {
                $key = $parts[0].Trim()
                $value = $parts[1].Trim()
                if ($key -match '^[A-Za-z_][A-Za-z0-9_]*$') {
                    Set-Item -Path "Env:$key" -Value $value
                }
            }
        }
    }
}

# Paths are configured via .env only
$repoRoot = $env:REPO_ROOT
$photonRoot = $env:PHOTON_ROOT
$webAssets = $env:WEB_ASSETS
$photonMode = if ($env:PHOTON_MODE) { $env:PHOTON_MODE.ToLowerInvariant() } else { "static" }
$photonDevUrl = if ($env:PHOTON_DEV_URL) { $env:PHOTON_DEV_URL.TrimEnd('/') } else { "http://10.0.2.2:5173" }
$photonDevHost = if ($env:PHOTON_DEV_HOST) { $env:PHOTON_DEV_HOST } else { "0.0.0.0" }
$photonDevPort = if ($env:PHOTON_DEV_PORT) { [int]$env:PHOTON_DEV_PORT } else { 5173 }

if (-not $repoRoot) { throw "REPO_ROOT not set in .env" }
if (-not $photonRoot) { throw "PHOTON_ROOT not set in .env" }
if (-not $webAssets) { throw "WEB_ASSETS not set in .env" }

$mobileRoot = Join-Path $repoRoot "mobile-app"

if (-not $InstanceUrl) { $InstanceUrl = $BackendUrl }

if ($photonMode -notin @("static", "dev")) { throw "PHOTON_MODE must be 'static' or 'dev'" }
$env:EXPO_PUBLIC_PHOTON_MODE = $photonMode

$repoRootBase = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($repoRoot)) { $repoRoot = Join-Path $repoRootBase $repoRoot }
$repoRoot = [IO.Path]::GetFullPath($repoRoot)
if (-not [IO.Path]::IsPathRooted($photonRoot)) { $photonRoot = Join-Path $repoRoot $photonRoot }
if (-not [IO.Path]::IsPathRooted($webAssets)) { $webAssets = Join-Path $repoRoot $webAssets }
$photonRoot = [IO.Path]::GetFullPath($photonRoot)
$webAssets = [IO.Path]::GetFullPath($webAssets)
$mobileRoot = Join-Path $repoRoot "mobile-app"

$devServer = $null
if ($photonMode -eq "dev") {
  $env:PUBLIC_BACKEND_URL = $BackendUrl
  $env:PUBLIC_INSTANCE_URL = $InstanceUrl
  Remove-Item Env:ADAPTER -ErrorAction SilentlyContinue
  Push-Location $photonRoot
  try {
    $devServer = Start-Process -FilePath "bun.exe" -ArgumentList @("run", "dev", "--", "--host", $photonDevHost, "--port", "$photonDevPort", "--strictPort") -WorkingDirectory $photonRoot -PassThru -WindowStyle Hidden
  } finally { Pop-Location }

  $healthUrl = "http://127.0.0.1:$photonDevPort/start.html"
  $serverReady = $false
  for ($attempt = 0; $attempt -lt 60; $attempt++) {
    if ($devServer.HasExited) { throw "Photon dev server exited before becoming ready" }
    try { Invoke-WebRequest -Uri $healthUrl -TimeoutSec 2 | Out-Null; $serverReady = $true; break } catch { Start-Sleep -Seconds 1 }
  }
  if (-not $serverReady) { Stop-Process -Id $devServer.Id -Force -ErrorAction SilentlyContinue; throw "Photon dev server did not become ready at $healthUrl" }
  $env:EXPO_PUBLIC_PHOTON_URL = "$photonDevUrl/start.html"
  Write-Host "Photon dev server running at $photonDevUrl/start.html (PID $($devServer.Id))"
} else {
  Remove-Item Env:EXPO_PUBLIC_PHOTON_URL -ErrorAction SilentlyContinue
  # Build Photon static assets for Android WebView
  Push-Location $photonRoot
  try {
    $previousAdapter = $env:ADAPTER
    $previousBackendUrl = $env:PUBLIC_BACKEND_URL
    $previousInstanceUrl = $env:PUBLIC_INSTANCE_URL
    $env:ADAPTER = "static"
    $env:PUBLIC_BACKEND_URL = $BackendUrl
    $env:PUBLIC_INSTANCE_URL = $InstanceUrl
    bun run build
    if ($LASTEXITCODE -ne 0) { throw "Photon static build failed" }
  } finally {
    $env:ADAPTER = $previousAdapter
    $env:PUBLIC_BACKEND_URL = $previousBackendUrl
    $env:PUBLIC_INSTANCE_URL = $previousInstanceUrl
    Pop-Location
  }

  $buildOutput = Join-Path $photonRoot "build"
  $androidEntryCandidates = @((Join-Path $buildOutput "start.html.html"), (Join-Path $buildOutput "start.html\index.html"), (Join-Path $buildOutput "start.html"))
  $androidEntry = $androidEntryCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $androidEntry) { throw "Photon static build did not emit the Android WebView route (expected start.html or start.html.html)" }
  $androidEntryPath = [IO.Path]::GetFullPath($androidEntry)
  $androidDestination = [IO.Path]::GetFullPath((Join-Path $buildOutput "start.html"))
  if ($androidEntryPath -ne $androidDestination) { Copy-Item -LiteralPath $androidEntry -Destination $androidDestination -Force }
  if (Test-Path $webAssets) { Remove-Item -LiteralPath $webAssets -Recurse -Force }
  New-Item -ItemType Directory -Path $webAssets -Force | Out-Null
  Copy-Item -Path (Join-Path $buildOutput "*") -Destination $webAssets -Recurse -Force
}

# Run the Android build and launch the emulator
Push-Location $mobileRoot
try {
  if (-not (Test-Path (Join-Path $mobileRoot "node_modules\react-native-webview\package.json"))) {
    throw "Install mobile-app dependencies first (npm install)"
  }
  
  npm.cmd run android
  if ($LASTEXITCODE -ne 0) { throw "Android build or launch failed" }
} finally {
  Pop-Location
}
