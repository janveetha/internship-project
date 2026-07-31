# =============================================================================
# Setup.ps1  â€” run from the unzipped deliverable root.
# Installs pre-published plugins to C:\plugins and registers the local NuGet
# feed so the extension source can restore NodeConfigurator.Abstractions.
# Idempotent: safe to run multiple times.
# =============================================================================
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==> NodeConfigurator setup" -ForegroundColor Cyan

# 1) Copy plugins to C:\plugins
$pluginsSrc = Join-Path $here "plugins"
$pluginsDst = "C:\plugins"
if (-not (Test-Path $pluginsSrc)) { Write-Host "[FAIL] plugins folder not found next to Setup.ps1" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $pluginsDst)) { New-Item -ItemType Directory -Path $pluginsDst -Force | Out-Null }
Copy-Item -Path (Join-Path $pluginsSrc "*") -Destination $pluginsDst -Recurse -Force
Write-Host "    [ok] Plugins copied to $pluginsDst" -ForegroundColor Green

# 2) Register local NuGet source
$feed = Join-Path $here "LocalNuget"
$feedName = "NodeConfiguratorLocal"
if (Test-Path $feed) {
	$existing = & dotnet nuget list source 2>$null
	if ($existing -match [regex]::Escape($feedName)) {
		& dotnet nuget update source $feedName --source $feed | Out-Null
		Write-Host "    [ok] Updated NuGet source '$feedName' -> $feed" -ForegroundColor Green
	}
	else {
		& dotnet nuget add source $feed --name $feedName | Out-Null
		Write-Host "    [ok] Added NuGet source '$feedName' -> $feed" -ForegroundColor Green
	}
}
else {
	Write-Host "    [warn] LocalNuget folder missing; extension source may not restore Abstractions." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1) powershell -ExecutionPolicy Bypass -File .\Verify.ps1"
Write-Host "  2) powershell -ExecutionPolicy Bypass -File .\Run-Host.ps1"
