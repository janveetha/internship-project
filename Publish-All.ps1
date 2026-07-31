# =============================================================================
# Publish-All.ps1 (optional) â€” rebuilds the plugins from the bundled Extension
# source and redeploys them to C:\plugins using each repo''s Deploy-Plugin.ps1.
# Requires the local NuGet feed registered by Setup.ps1 (for Abstractions).
# =============================================================================
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$map = @(
	@{ Dir = "Extensions\Extension.Identity";    PluginId = "identity" },
	@{ Dir = "Extensions\Extension.CentralNode"; PluginId = "centralnode" },
	@{ Dir = "Extensions\Extension.Mode";        PluginId = "mode" }
)

foreach ($m in $map) {
	$repo = Join-Path $here $m.Dir
	$deploy = Join-Path $repo "Deploy-Plugin.ps1"
	if (-not (Test-Path $deploy)) {
		Write-Host "[warn] No Deploy-Plugin.ps1 in $repo; skipping." -ForegroundColor Yellow
		continue
	}
	Write-Host "==> Publishing $($m.PluginId) from $repo" -ForegroundColor Cyan
	Push-Location $repo
	try {
		& $deploy -PluginId $m.PluginId -Version "1.0.0" -PluginsRoot "C:\plugins"
	}
	finally { Pop-Location }
}
Write-Host "Done. Run Verify.ps1 to confirm." -ForegroundColor Green
