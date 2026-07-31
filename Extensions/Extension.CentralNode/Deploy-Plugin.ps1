# Deploy-Plugin.ps1
# Builds (publish) and deploys the CentralNode extension to the host's plugin folder,
# then verifies the isolated dependencies are present in the output.

param(
    [string]$PluginId    = "centralnode",
    [string]$Version     = "1.0.0",
    [string]$PluginsRoot = "C:\plugins",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$projectDir  = "NodeConfigurator.Extensions.CentralNode"
$project     = Join-Path $projectDir "NodeConfigurator.Extensions.CentralNode.csproj"
$dest        = Join-Path (Join-Path $PluginsRoot $PluginId) $Version

Write-Host "Publishing $PluginId v$Version ($Configuration) to $dest ..." -ForegroundColor Cyan

# 1. Ensure destination is empty to avoid stale files.
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory -Path $dest -Force | Out-Null

# 2. Publish straight into the destination folder.
dotnet publish $project -c $Configuration -o $dest
if ($LASTEXITCODE -ne 0) {
    Write-Host "Publish failed!" -ForegroundColor Red
    exit 1
}

# 3. Copy manifest.json (and wwwroot static assets if present).
Copy-Item (Join-Path $projectDir "manifest.json") -Destination $dest -Force

$wwwroot = Join-Path $projectDir "wwwroot"
if (Test-Path $wwwroot) { Copy-Item $wwwroot -Destination $dest -Recurse -Force }

# 4. Verify the required files exist; fail loudly if any are missing.
$required = @("*.deps.json", "Newtonsoft.Json.dll", "Markdig.dll")
$missing  = @()
foreach ($pattern in $required) {
    if (-not (Get-ChildItem -Path $dest -Filter $pattern -File -ErrorAction SilentlyContinue)) {
        $missing += $pattern
    }
}

if ($missing.Count -gt 0) {
    Write-Host "Deployment verification FAILED. Missing from ${dest}:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "Check <PublishTrimmed>false</PublishTrimmed> and that IsolationSmokeTest.Run touches both packages." -ForegroundColor Yellow
    exit 1
}

Write-Host "Deployed and verified successfully!" -ForegroundColor Green
Get-ChildItem $dest -Recurse | Select-Object FullName
