$ErrorActionPreference = 'Stop'
$azBundle = Join-Path $PSScriptRoot '../build/windows/x64/runner/Release'
foreach ($azRequired in @('AZUtility.exe', 'flutter_windows.dll', 'data/icudtl.dat', 'data/flutter_assets', 'data/app.so')) {
    if (-not (Test-Path -LiteralPath (Join-Path $azBundle $azRequired))) { throw "Missing runtime component: $azRequired" }
}
$azDist = Join-Path $PSScriptRoot '../dist'
New-Item -ItemType Directory -Force $azDist | Out-Null
$azName = 'AZUtility-v1.0.0-windows-x64.zip'
Compress-Archive -Path (Join-Path $azBundle '*') -DestinationPath (Join-Path $azDist $azName) -Force
$azHash = (Get-FileHash -Algorithm SHA256 (Join-Path $azDist $azName)).Hash.ToLowerInvariant()
"$azHash  $azName" | Set-Content (Join-Path $azDist 'SHA256SUMS-windows.txt')
'Windows executable is unsigned. Extract the entire ZIP and keep all companion files together.' | Set-Content (Join-Path $azDist 'WINDOWS-SIGNING.txt')
