<#
	Build-AvevaDeck.ps1
	Generates an AVEVA-branded PowerPoint deck for the NodeConfigurator
	Runtime Plugin Architecture (Phase 3), matching the supplied template:
	  - dark particle-style title slide with "INTERNAL USE ONLY" badge
	  - purple section titles with a warm gradient accent line
	  - AVEVA footer + wordmark on every content slide
	  - a native-shape recreation of the Phase 3 isolation diagram

	Requires: Microsoft PowerPoint (COM automation).
	Output  : .\NodeConfigurator_Phase3_AVEVA.pptx
#>

param(
	[string]$OutputPath = (Join-Path (Resolve-Path ".").Path "NodeConfigurator_Phase3_AVEVA.pptx"),
	[string]$PresenterName = "Name",
	[string]$PresentationDate = (Get-Date -Format "dd MMMM yyyy")
)

$ErrorActionPreference = "Stop"

# --------------------------- brand palette -----------------------------------
$AvevaPurple   = 0x6A1B7A   # deep purple (BGR for COM: stored below via RGB helper)
# PowerPoint OLE color is 0x00BBGGRR. Build via helper to avoid confusion.
function RGB([int]$r, [int]$g, [int]$b) { return ($b -shl 16) -bor ($g -shl 8) -bor $r }

$ClrPurple   = RGB 74  10  91     # titles / primary brand
$ClrPurpleD  = RGB 45  10  70     # dark panel accents
$ClrPink     = RGB 226 0   116    # badge + accent gradient start
$ClrOrange   = RGB 243 146 0      # accent gradient end
$ClrDarkBg   = RGB 20  8   28     # title slide background
$ClrDarkBg2  = RGB 40  16  55     # title slide gradient stop
$ClrWhite    = RGB 255 255 255
$ClrGrayText = RGB 90  90  90
$ClrHostBox  = RGB 236 236 240
$ClrHostEdge = RGB 150 150 160
$ClrAlcBox   = RGB 224 224 232
$ClrEntry    = RGB 210 200 225
$ClrDep      = RGB 205 220 235
$ClrBus      = RGB 90  70  110
$ClrArrow    = RGB 120 120 130

# Enum constants
$msoShapeRectangle        = 1
$msoShapeRoundedRectangle = 5
$msoShapeRightArrow       = 33
$msoTrue                  = -1
$msoFalse                 = 0
$ppLayoutBlank            = 12
$ppAlignLeft              = 1
$ppAlignCenter            = 2
$ppAlignRight             = 3
$msoAnchorMiddle          = 3
$msoConnectorStraight     = 1

# --------------------------- helpers -----------------------------------------
$ppt  = New-Object -ComObject PowerPoint.Application
$pres = $ppt.Presentations.Add()
# 16:9 widescreen (in points: 13.333in x 7.5in)
$pres.PageSetup.SlideWidth  = 960
$pres.PageSetup.SlideHeight = 540
$SW = 960; $SH = 540

function Add-Slide { $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank) }

function New-Box {
	param($slide, [single]$L, [single]$T, [single]$W, [single]$H,
		  [int]$shape = $msoShapeRoundedRectangle)
	$slide.Shapes.AddShape($shape, $L, $T, $W, $H)
}

function Style-Fill {
	param($shp, [int]$color, [int]$lineColor = -1, [single]$lineWeight = 1)
	$shp.Fill.ForeColor.RGB = $color
	$shp.Fill.Visible = $msoTrue
	if ($lineColor -ge 0) {
		$shp.Line.ForeColor.RGB = $lineColor
		$shp.Line.Weight = [single]$lineWeight
		$shp.Line.Visible = $msoTrue
	} else {
		$shp.Line.Visible = $msoFalse
	}
	$shp.Shadow.Visible = $msoFalse
}

function Set-Text {
	param($shp, [string]$text, [int]$size = 14, [int]$color = 0,
		  [bool]$bold = $false, [int]$align = $ppAlignCenter)
	$tf = $shp.TextFrame
	$tf.WordWrap = $msoTrue
	$tf.MarginLeft = 6; $tf.MarginRight = 6; $tf.MarginTop = 3; $tf.MarginBottom = 3
	$tf.VerticalAnchor = $msoAnchorMiddle
	$tr = $tf.TextRange
	$tr.Text = $text
	$tr.Font.Size = [single]$size
	$tr.Font.Name = "Segoe UI"
	$tr.Font.Color.RGB = $color
	$tr.Font.Bold = $(if ($bold) { $msoTrue } else { $msoFalse })
	$tr.ParagraphFormat.Alignment = $align
}

function Add-TextBox {
	param($slide, [single]$L, [single]$T, [single]$W, [single]$H,
		  [string]$text, [int]$size = 14, [int]$color = 0,
		  [bool]$bold = $false, [int]$align = $ppAlignLeft)
	$tb = $slide.Shapes.AddTextbox(1, $L, $T, $W, $H)  # 1 = horizontal
	Set-Text $tb $text $size $color $bold $align
	$tb.TextFrame.VerticalAnchor = $msoAnchorMiddle
	$tb
}

function Add-AccentLine {
	param($slide, [single]$L, [single]$T, [single]$W = 90, [single]$H = 4)
	$ln = $slide.Shapes.AddShape($msoShapeRectangle, $L, $T, $W, $H)
	$ln.Line.Visible = $msoFalse
	$ln.Fill.TwoColorGradient(1, 1)  # horizontal
	$ln.Fill.ForeColor.RGB = $ClrOrange
	$ln.Fill.BackColor.RGB = $ClrPink
	$ln.Shadow.Visible = $msoFalse
}

function Add-Footer {
	param($slide, [bool]$dark = $false)
	$col = $(if ($dark) { RGB 200 190 210 } else { $ClrGrayText })
	Add-TextBox $slide 24 ($SH-24) 620 16 `
		"For Internal Use Only. (c)$((Get-Date).Year) AVEVA Group plc and its subsidiaries. All rights reserved." `
		8 $col $false $ppAlignLeft | Out-Null
	$logo = Add-TextBox $slide ($SW-150) ($SH-40) 130 26 "AVEVA" 20 `
		$(if ($dark) { $ClrWhite } else { $ClrPurple }) $true $ppAlignRight
	$logo.TextFrame.TextRange.Font.Name = "Segoe UI Semibold"
}

function Add-ContentTitle {
	param($slide, [string]$title)
	Add-AccentLine $slide 40 40 90 4
	Add-TextBox $slide 38 52 860 44 $title 26 $ClrPurple $true $ppAlignLeft | Out-Null
	Add-Footer $slide $false
}

function Add-Bullets {
	param($slide, [single]$L, [single]$T, [single]$W, [single]$H, [string[]]$items, [int]$size = 16)
	$tb = $slide.Shapes.AddTextbox(1, $L, $T, $W, $H)
	$tf = $tb.TextFrame; $tf.WordWrap = $msoTrue
	$tr = $tf.TextRange
	$tr.Text = ($items -join "`r")
	$tr.Font.Size = [single]$size
	$tr.Font.Name = "Segoe UI"
	$tr.Font.Color.RGB = (RGB 45 45 55)
	$tr.ParagraphFormat.Alignment = $ppAlignLeft
	$tr.ParagraphFormat.Bullet.Visible = $msoTrue
	$tr.ParagraphFormat.SpaceAfter = 8
	$tb
}

Write-Host "Building AVEVA-branded deck..." -ForegroundColor Cyan

# ============================================================================
# SLIDE 1 — Title (dark, particle-style)
# ============================================================================
$s = Add-Slide
$bg = $s.Shapes.AddShape($msoShapeRectangle, 0, 0, $SW, $SH)
$bg.Line.Visible = $msoFalse
$bg.Fill.TwoColorGradient(5, 1)   # diagonal gradient
$bg.Fill.ForeColor.RGB = $ClrDarkBg
$bg.Fill.BackColor.RGB = $ClrDarkBg2
$bg.Shadow.Visible = $msoFalse

# scatter subtle "particles"
$rand = [System.Random]::new(7)
for ($i = 0; $i -lt 90; $i++) {
	$d = [single]($rand.Next(2, 6))
	$x = [single]($rand.Next(0, $SW)); $y = [single]($rand.Next(0, $SH))
	$dot = $s.Shapes.AddShape(9, $x, $y, $d, $d)  # 9 = oval
	$dot.Line.Visible = $msoFalse
	$dot.Fill.ForeColor.RGB = (RGB 180 130 210)
	$dot.Fill.Transparency = [single](0.4 + $rand.NextDouble() * 0.5)
	$dot.Shadow.Visible = $msoFalse
}

# INTERNAL USE ONLY badge
$badge = $s.Shapes.AddShape($msoShapeRectangle, 40, 34, 150, 22)
Style-Fill $badge $ClrPink
Set-Text $badge "INTERNAL USE ONLY" 9 $ClrWhite $true $ppAlignCenter

Add-TextBox $s 42 300 200 20 "DATE" 12 $ClrWhite $true $ppAlignLeft | Out-Null
Add-AccentLine $s 44 322 120 4
Add-TextBox $s 40 336 820 70 "NodeConfigurator - Runtime Plugin Architecture" 40 $ClrWhite $true $ppAlignLeft | Out-Null
Add-TextBox $s 42 470 700 26 $PresenterName 20 $ClrWhite $true $ppAlignLeft | Out-Null
Add-TextBox $s 42 300 200 20 $PresentationDate 11 (RGB 210 190 220) $false $ppAlignLeft | Out-Null
Add-Footer $s $true

# ============================================================================
# SLIDE 2 — Agenda / Overview
# ============================================================================
$s = Add-Slide
Add-ContentTitle $s "Overview"
Add-Bullets $s 44 120 870 360 @(
	"The problem: independent teams ship UI plugins without recompiling or redeploying the host.",
	"The host discovers plugins on disk at startup and loads each into its own isolated AssemblyLoadContext (ALC).",
	"Dependency isolation: two plugins can use different versions of the same library (Newtonsoft.Json 12 vs 13, Markdig 0.31 vs 0.38).",
	"A minimal, stable contract: plugins reference only NodeConfigurator.Abstractions (the IExtension contract).",
	"Fault tolerance: a bad plugin is logged and skipped - it never crashes the host."
) 18 | Out-Null

# ============================================================================
# SLIDE 3 — Phase 1 + 2 summary (single slide)
# ============================================================================
$s = Add-Slide
Add-ContentTitle $s "Phases 1 & 2 - Foundation (Summary)"
Add-Bullets $s 44 120 430 360 @(
	"Phase 1 - Contract & shell",
	"Defined IExtension + IExtensionContext.",
	"Built the MAUI Blazor Hybrid host shell.",
	"Rendered plugin Razor UI via DynamicComponent."
) 16 | Out-Null
Add-Bullets $s 500 120 420 360 @(
	"Phase 2 - Discovery & lifecycle",
	"Manifest-driven discovery (manifest.json).",
	"Highest-version selection per plugin id.",
	"Event bus + snapshot persistence (AppSnapshot)."
) 16 | Out-Null

# ============================================================================
# SLIDE 4 — Phase 3 architecture diagram (native shapes)
# ============================================================================
$s = Add-Slide
Add-ContentTitle $s "Phase 3 - Runtime Plugin Isolation (ALC per Plugin)"

# Host Solution panel (left)
$hostPanel = New-Box $s 40 120 190 250 $msoShapeRectangle
Style-Fill $hostPanel $ClrHostBox $ClrHostEdge 1.25
Add-TextBox $s 40 122 190 20 "Host Solution" 11 (RGB 70 70 80) $true $ppAlignCenter | Out-Null

$hb1 = New-Box $s 54 150 162 40; Style-Fill $hb1 $ClrWhite $ClrHostEdge 1
Set-Text $hb1 "NodeConfigurator.Host" 10 (RGB 40 40 50) $false $ppAlignCenter
$hb2 = New-Box $s 54 200 162 54; Style-Fill $hb2 $ClrWhite $ClrHostEdge 1
Set-Text $hb2 "NodeConfigurator.Core`n(PluginLoader, PluginLoadContext)" 9 (RGB 40 40 50) $false $ppAlignCenter
$hb3 = New-Box $s 54 264 162 44; Style-Fill $hb3 $ClrWhite $ClrHostEdge 1
Set-Text $hb3 "NodeConfigurator.Abstractions (NuGet)" 9 (RGB 40 40 50) $false $ppAlignCenter

# Boundary note
$bnote = New-Box $s 40 322 190 46 $msoShapeRoundedRectangle
Style-Fill $bnote (RGB 246 240 210) (RGB 200 180 120) 1
Set-Text $bnote "Boundary (shared): Abstractions + Blazor + System.Text.Json + JSInterop" 8 (RGB 90 70 20) $false $ppAlignCenter

# Runtime loader arrow (center top)
$rl = $s.Shapes.AddShape($msoShapeRightArrow, 250, 128, 460, 30)
Style-Fill $rl (RGB 170 170 180)
Set-Text $rl "Runtime Plugin Loader:  Discover -> Read manifest.json -> Select highest version -> Load" 9 $ClrWhite $true $ppAlignCenter

# Three ALC columns
$alcData = @(
	@{ X = 250; Name = "Plugin:identity" },
	@{ X = 405; Name = "Plugin:centralnode" },
	@{ X = 560; Name = "Plugin:mode" }
)
foreach ($a in $alcData) {
	$x = [single]$a.X
	$alc = New-Box $s $x 172 145 150 $msoShapeRectangle
	Style-Fill $alc $ClrAlcBox (RGB 160 160 175) 1
	Add-TextBox $s $x 174 145 26 "AssemblyLoadContext:`n$($a.Name)" 8 (RGB 60 60 75) $true $ppAlignCenter | Out-Null
	$e = New-Box $s ($x+10) 208 125 42; Style-Fill $e $ClrEntry (RGB 150 140 170) 1
	Set-Text $e "Plugin Entry Assembly" 9 (RGB 45 40 60) $false $ppAlignCenter
	$d = New-Box $s ($x+10) 258 125 50; Style-Fill $d $ClrDep (RGB 140 160 185) 1
	Set-Text $d "Private Dependencies" 9 (RGB 30 45 65) $false $ppAlignCenter
}

# Isolated note
$inote = New-Box $s 380 330 190 34 $msoShapeRoundedRectangle
Style-Fill $inote (RGB 224 236 224) (RGB 150 190 150) 1
Set-Text $inote "Isolated (per plugin): Newtonsoft.Json, Markdig, etc." 8 (RGB 30 70 30) $false $ppAlignCenter

# Deployment folder panel (right)
$dep = New-Box $s 730 120 190 250 $msoShapeRectangle
Style-Fill $dep $ClrHostBox $ClrHostEdge 1.25
Add-TextBox $s 730 122 190 30 "Plugin Deployment Folder: C:\plugins\" 10 (RGB 70 70 80) $true $ppAlignCenter | Out-Null
$folders = @("identity\1.0.0", "centralnode\1.0.0", "mode\1.0.0")
$fy = 168
foreach ($f in $folders) {
	$fb = New-Box $s 748 $fy 154 46 $msoShapeRectangle
	Style-Fill $fb $ClrWhite $ClrHostEdge 1
	Set-Text $fb $f 10 (RGB 40 40 50) $false $ppAlignCenter
	$fy += 58
}

# Event bus (bottom, full width under columns)
$bus = New-Box $s 250 384 455 34 $msoShapeRectangle
Style-Fill $bus $ClrBus
Set-Text $bus "In-memory Pub/Sub Event Bus" 12 $ClrWhite $true $ppAlignCenter

# ============================================================================
# SLIDE 5 — Dependency isolation proof
# ============================================================================
$s = Add-Slide
Add-ContentTitle $s "Dependency Isolation - Proven"
Add-TextBox $s 44 120 870 30 "Two plugins load different versions of the same libraries simultaneously - each from its own ALC." 15 (RGB 60 60 70) $false $ppAlignLeft | Out-Null

# simple table
$rows = @(
	@("Plugin", "Newtonsoft.Json", "Markdig", "ALC"),
	@("Identity (ext.identity)", "12.0.3", "0.31.0", "Plugin:ext.identity"),
	@("CentralNode (ext.central)", "13.0.3", "0.38.0", "Plugin:ext.central")
)
$colX = @(44, 300, 470, 620); $colW = @(256, 170, 150, 300)
$ry = 170
for ($r = 0; $r -lt $rows.Count; $r++) {
	for ($c = 0; $c -lt 4; $c++) {
		$cell = New-Box $s $colX[$c] $ry $colW[$c] 40 $msoShapeRectangle
		if ($r -eq 0) { Style-Fill $cell $ClrPurple; $tc = $ClrWhite; $bold = $true }
		else { Style-Fill $cell (RGB 244 242 248) (RGB 210 205 220) 0.75; $tc = (RGB 40 40 50); $bold = $false }
		Set-Text $cell $rows[$r][$c] 12 $tc $bold $ppAlignCenter
	}
	$ry += 42
}
Add-TextBox $s 44 320 870 60 "Because Newtonsoft.Json and Markdig are NOT boundary assemblies, each resolves from the plugin's own folder via its .deps.json - no conflict, different ALC names, different paths." 13 (RGB 70 70 80) $false $ppAlignLeft | Out-Null

# ============================================================================
# SLIDE 6 — Runtime flow
# ============================================================================
$s = Add-Slide
Add-ContentTitle $s "Runtime Flow - Launch to Persistence"
Add-Bullets $s 44 120 870 380 @(
	"Startup - the MAUI Blazor Hybrid host boots and builds its DI container.",
	"Plugin load - PluginLoader discovers, version-selects, and loads each plugin into its own PluginLoadContext; instantiates each IExtension.",
	"Initialize & hydrate - AppInitializer loads the saved AppSnapshot, then calls InitializeAsync + HydrateAsync per extension.",
	"UI render - each extension's ComponentType is rendered with Blazor DynamicComponent.",
	"Events - user actions publish on the shared IEventBus; subscribed extensions react.",
	"Persistence - SaveCoordinator calls SerializeConfig() on every extension and writes one AppSnapshot via IStateStore (atomic write)."
) 15 | Out-Null

# ============================================================================
# SLIDE 7 — Thank you
# ============================================================================
$s = Add-Slide
$bg = $s.Shapes.AddShape($msoShapeRectangle, 0, 0, $SW, $SH)
$bg.Line.Visible = $msoFalse
$bg.Fill.TwoColorGradient(5, 1)
$bg.Fill.ForeColor.RGB = $ClrDarkBg
$bg.Fill.BackColor.RGB = $ClrDarkBg2
$bg.Shadow.Visible = $msoFalse
Add-AccentLine $s 44 250 120 4
Add-TextBox $s 40 264 820 60 "Thank You" 44 $ClrWhite $true $ppAlignLeft | Out-Null
Add-TextBox $s 42 336 820 30 "Questions?" 18 (RGB 210 190 220) $false $ppAlignLeft | Out-Null
Add-Footer $s $true

# --------------------------- save --------------------------------------------
if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }
$pres.SaveAs($OutputPath)
$pres.Close()
$ppt.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ppt) | Out-Null

Write-Host "Deck created: $OutputPath" -ForegroundColor Green
