# Deploy-Plugin.ps1
param(
    [string]$Configuration = "Release",
    [string]$PluginPath = "C:\plugins\mode\1.0.0"
)
$ErrorActionPreference = "Stop"
Write-Host "Building extension..." -ForegroundColor Cyan
dotnet build -c $Configuration
if ($LASTEXITCODE -ne 0) { Write-Host "Build failed!" -ForegroundColor Red; exit 1 }
$outputPath = "NodeConfigurator.Extensions.Mode\bin\$Configuration\net10.0"
Write-Host "Deploying to $PluginPath..." -ForegroundColor Cyan
if (Test-Path $PluginPath) { Remove-Item $PluginPath -Recurse -Force }
New-Item -ItemType Directory -Path $PluginPath -Force | Out-Null
Copy-Item "$outputPath\*.dll" -Destination $PluginPath -Force
Copy-Item "$outputPath\*.deps.json" -Destination $PluginPath -Force
Copy-Item "$outputPath\*.runtimeconfig.json" -Destination $PluginPath -Force -ErrorAction SilentlyContinue
Copy-Item "NodeConfigurator.Extensions.Mode\manifest.json" -Destination $PluginPath -Force
$wwwroot = "NodeConfigurator.Extensions.Mode\wwwroot"
if (Test-Path $wwwroot) { Copy-Item $wwwroot -Destination $PluginPath -Recurse -Force }
Write-Host "Deployed successfully!" -ForegroundColor Green
