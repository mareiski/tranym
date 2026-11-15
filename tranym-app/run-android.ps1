# This script builds the Photon static assets for the mobile app, 
# copies the dist to the app's assets directory, and runs the app on android.

param(
  [string]$BackendUrl = "http://10.0.2.2:1236",
  [string]$InstanceUrl = ""
)

# cancel on any error
$ErrorActionPreference = "Stop"

# Paths are configured via .env only
$repoRoot = $env:REPO_ROOT
$photonRoot = $env:PHOTON_ROOT
$mobileRoot = Join-Path $repoRoot "mobile-app"
$webAssets = $env:WEB_ASSETS

if (-not $repoRoot) { throw "REPO_ROOT not set in .env" }
if (-not $photonRoot) { throw "PHOTON_ROOT not set in .env" }
if (-not $webAssets) { throw "WEB_ASSETS not set in .env" }

if (-not $InstanceUrl) { $InstanceUrl = $BackendUrl }

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
                $env:$key = $value
            }
        }
    }
}

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
$androidEntryCandidates = @(
  (Join-Path $buildOutput "start.html.html"),
  (Join-Path $buildOutput "start.html\index.html"),
  (Join-Path $buildOutput "start.html")
)
$androidEntry = $androidEntryCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $androidEntry) {
  throw "Photon static build did not emit the Android WebView route (expected start.html or start.html.html)"
}
$androidEntryPath = [IO.Path]::GetFullPath($androidEntry)
$androidDestination = [IO.Path]::GetFullPath((Join-Path $buildOutput "start.html"))
if ($androidEntryPath -ne $androidDestination) {
  Copy-Item -LiteralPath $androidEntry -Destination $androidDestination -Force
}

# Copy the Photon static build output to the Android app's assets directory
if (Test-Path $webAssets) {
  Remove-Item -LiteralPath $webAssets -Recurse -Force
}
New-Item -ItemType Directory -Path $webAssets -Force | Out-Null
Copy-Item -Path (Join-Path $buildOutput "*") -Destination $webAssets -Recurse -Force

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
