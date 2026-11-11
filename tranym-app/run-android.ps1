param(
  [string]$BackendUrl = "http://10.0.2.2:1236",
  [string]$InstanceUrl = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$photonRoot = Join-Path $repoRoot "photon"
$mobileRoot = Join-Path $repoRoot "mobile-app"
$webAssets = Join-Path $mobileRoot "android\app\src\main\assets\photon"
if (-not $InstanceUrl) { $InstanceUrl = $BackendUrl }

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

if (Test-Path $webAssets) {
  Remove-Item -LiteralPath $webAssets -Recurse -Force
}
New-Item -ItemType Directory -Path $webAssets -Force | Out-Null
Copy-Item -Path (Join-Path $buildOutput "*") -Destination $webAssets -Recurse -Force

Push-Location $mobileRoot
try {
  if (-not (Test-Path (Join-Path $mobileRoot "node_modules\react-native-webview\package.json"))) {
    throw "Install mobile-app dependencies first (npm install)"
  }
  $previousCleartext = $env:TRYNAM_ALLOW_CLEARTEXT
  $env:TRYNAM_ALLOW_CLEARTEXT = "1"
  npm.cmd run android
  if ($LASTEXITCODE -ne 0) { throw "Android build or launch failed" }
} finally {
  $env:TRYNAM_ALLOW_CLEARTEXT = $previousCleartext
  Pop-Location
}
