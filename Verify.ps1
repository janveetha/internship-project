# =============================================================================
# Verify.ps1 â€” confirms plugins are correctly installed at C:\plugins.
# Exits non-zero if anything required is missing.
# =============================================================================
$ErrorActionPreference = "Stop"
$pluginsDst = "C:\plugins"
$expected = @("identity", "centralnode", "mode")
$rows = @()
$failures = 0

Write-Host "==> Verifying plugins under $pluginsDst" -ForegroundColor Cyan

if (-not (Test-Path $pluginsDst)) {
	Write-Host "[FAIL] $pluginsDst does not exist. Run Setup.ps1 first." -ForegroundColor Red
	exit 1
}

foreach ($plugId in $expected) {
	$pidPath = Join-Path $pluginsDst $plugId
	if (-not (Test-Path $pidPath)) {
		Write-Host "[FAIL] Missing plugin folder: $pidPath" -ForegroundColor Red
		$failures++
		continue
	}
	$versionDirs = Get-ChildItem $pidPath -Directory -ErrorAction SilentlyContinue
	if (-not $versionDirs) {
		Write-Host "[FAIL] No version folders under $pidPath" -ForegroundColor Red
		$failures++
		continue
	}
	foreach ($vdir in $versionDirs) {
		$hasManifest = Test-Path (Join-Path $vdir.FullName "manifest.json")
		$hasDeps     = [bool](Get-ChildItem $vdir.FullName -Filter "*.deps.json" -File -ErrorAction SilentlyContinue)
		$entryOk     = $false
		$entryName   = "?"
		if ($hasManifest) {
			try {
				$m = Get-Content (Join-Path $vdir.FullName "manifest.json") -Raw | ConvertFrom-Json
				$entryName = $m.entryAssembly
				$entryOk = (-not [string]::IsNullOrWhiteSpace($entryName)) -and (Test-Path (Join-Path $vdir.FullName $entryName))
			} catch { $entryOk = $false }
		}
		$ok = $hasManifest -and $hasDeps -and $entryOk
		if (-not $ok) { $failures++ }
		$rows += [pscustomobject]@{
			Plugin   = $plugId
			Version  = $vdir.Name
			Manifest = $(if($hasManifest){"yes"}else{"NO"})
			Deps     = $(if($hasDeps){"yes"}else{"NO"})
			Entry    = $(if($entryOk){$entryName}else{"MISSING"})
			Status   = $(if($ok){"OK"}else{"FAIL"})
		}
	}
}

$rows | Format-Table -AutoSize

if ($failures -gt 0) {
	Write-Host "Verification FAILED with $failures problem(s)." -ForegroundColor Red
	exit 1
}
Write-Host "All plugins verified successfully." -ForegroundColor Green
exit 0
