# =============================================================================
# Run-Host.ps1 â€” launches the NodeConfigurator host.
# Tries `dotnet run`; if that fails (e.g. missing MAUI workload), prints the
# exact solution path to open in Visual Studio and press F5.
# =============================================================================
$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$hostProjDir = Join-Path $here "Host\NodeConfigurator.Host\NodeConfigurator.Host"
$slnPath     = Join-Path $here "Host\NodeConfigurator.Host\NodeConfigurator.Host.slnx"

Write-Host "==> Running NodeConfigurator host" -ForegroundColor Cyan
Write-Host "    Reminder: plugins are expected at C:\plugins (Setup.ps1 ensures this)." -ForegroundColor Yellow

$csproj = Get-ChildItem $hostProjDir -Filter "*.csproj" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($csproj) {
	Write-Host "    Attempting: dotnet run --project `"$($csproj.FullName)`"" -ForegroundColor Cyan
	& dotnet run --project $csproj.FullName
	if ($LASTEXITCODE -eq 0) { exit 0 }
	Write-Host "    [warn] dotnet run did not complete cleanly (exit $LASTEXITCODE)." -ForegroundColor Yellow
}
else {
	Write-Host "    [warn] Host .csproj not found under $hostProjDir." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Could not launch via dotnet run (a MAUI workload may be required)." -ForegroundColor Yellow
Write-Host "Open the solution in Visual Studio and press F5:" -ForegroundColor Cyan
Write-Host "    $slnPath"
Write-Host ""
Write-Host "If the MAUI workload is missing, install it with:" -ForegroundColor Cyan
Write-Host "    dotnet workload install maui"
