# Build-Phase3-Deck.ps1
# Generates NodeConfigurator_Phase3.pptx via PowerPoint COM automation.

$ErrorActionPreference = "Stop"
$OutPath = Join-Path (Get-Location) "NodeConfigurator_Phase3.pptx"
if (Test-Path $OutPath) { Remove-Item $OutPath -Force }

function RGB([int]$r,[int]$g,[int]$b){ return ($r + ($g*256) + ($b*65536)) }

# Palette
$cTitle   = RGB 31 56 100
$cSub     = RGB 90 90 90
$cWhite   = RGB 255 255 255
$cText    = RGB 33 33 33
$blueF    = RGB 217 234 247 ; $blueL = RGB 41 128 185
$greenF   = RGB 214 234 214 ; $greenL = RGB 76 175 80
$orangeF  = RGB 253 222 190 ; $orangeL = RGB 230 126 34
$purpleF  = RGB 226 214 240 ; $purpleL = RGB 142 68 173
$tanF     = RGB 224 214 190 ; $tanL = RGB 150 120 70
$grayF    = RGB 226 226 226 ; $grayL = RGB 120 120 120
$yellowF  = RGB 253 245 205 ; $yellowL = RGB 214 180 80
$hostF    = RGB 245 247 250 ; $hostL = RGB 90 90 90
$bandF    = RGB 31 56 100

# enums
$ppLayoutBlank = 12
$msoRect = 1
$msoRoundRect = 5
$msoRightArrow = 33
$alignL = 1 ; $alignC = 2 ; $alignR = 3
$msoTrue = -1 ; $msoFalse = 0
$arrowTriangle = 2

$app = New-Object -ComObject PowerPoint.Application
$app.Visible = $msoTrue
$pres = $app.Presentations.Add($msoTrue)
$pres.PageSetup.SlideWidth  = 960
$pres.PageSetup.SlideHeight = 540
$W = 960 ; $H = 540

function Add-Slide {
	$idx = $pres.Slides.Count + 1
	return $pres.Slides.Add($idx, $ppLayoutBlank)
}

function Add-Text($slide,$l,$t,$w,$h,$text,$size,$bold,$color,$align){
	$tb = $slide.Shapes.AddTextbox(1,$l,$t,$w,$h)
	$tf = $tb.TextFrame
	$tf.WordWrap = $msoTrue
	$tf.TextRange.Text = $text
	[single]$sz = $size
	$tf.TextRange.Font.Size = $sz
	$tf.TextRange.Font.Bold = $(if($bold){$msoTrue}else{$msoFalse})
	$tf.TextRange.Font.Color.RGB = $color
	$tf.TextRange.Font.Name = "Segoe UI"
	$tf.TextRange.ParagraphFormat.Alignment = $align
	$tf.MarginTop = 2 ; $tf.MarginBottom = 2 ; $tf.MarginLeft = 4 ; $tf.MarginRight = 4
	return $tb
}

function Add-Bullets($slide,$l,$t,$w,$h,$lines,$size,$color){
	$tb = $slide.Shapes.AddTextbox(1,$l,$t,$w,$h)
	$tf = $tb.TextFrame
	$tf.WordWrap = $msoTrue
	$tf.TextRange.Text = ($lines -join [string][char]13)
	[single]$sz = $size
	$tf.TextRange.Font.Size = $sz
	$tf.TextRange.Font.Color.RGB = $color
	$tf.TextRange.Font.Name = "Segoe UI"
	$tf.TextRange.ParagraphFormat.Alignment = $alignL
	$tf.TextRange.ParagraphFormat.SpaceAfter = 6
	return $tb
}

function Add-Box($slide,$shape,$l,$t,$w,$h,$fill,$line,$text,$size,$bold,$font,$lweight){
	$s = $slide.Shapes.AddShape($shape,$l,$t,$w,$h)
	$s.Fill.ForeColor.RGB = $fill
	$s.Line.ForeColor.RGB = $line
	[single]$wt = $(if($lweight){$lweight}else{1.25})
	$s.Line.Weight = $wt
	if($null -ne $text){
		$tr = $s.TextFrame.TextRange
		$tr.Text = $text
		[single]$sz = $size
		$tr.Font.Size = $sz
		$tr.Font.Bold = $(if($bold){$msoTrue}else{$msoFalse})
		$tr.Font.Color.RGB = $font
		$tr.Font.Name = "Segoe UI"
		$tr.ParagraphFormat.Alignment = $alignC
		$s.TextFrame.VerticalAnchor = 3  # middle
		$s.TextFrame.WordWrap = $msoTrue
	}
	return $s
}

function Add-Arrow($slide,$x1,$y1,$x2,$y2,$color,$weight,$dash){
	$ln = $slide.Shapes.AddLine($x1,$y1,$x2,$y2)
	$ln.Line.ForeColor.RGB = $color
	[single]$wt = $(if($weight){$weight}else{1.75})
	$ln.Line.Weight = $wt
	$ln.Line.EndArrowheadStyle = $arrowTriangle
	if($dash){ $ln.Line.DashStyle = 4 } # dash
	return $ln
}

function Add-TitleBand($slide,$title){
	$band = Add-Box $slide $msoRect 0 0 $W 64 $bandF $bandF $null 0 $false $cWhite 0
	$band.Line.Visible = $msoFalse
	Add-Text $slide 30 12 ($W-60) 44 $title 26 $true $cWhite $alignL | Out-Null
}

# ============================================================
# SLIDE 1 — TITLE
# ============================================================
$s = Add-Slide
Add-Box $s $msoRect 0 0 $W $H $bandF $bandF $null 0 $false $cWhite 0 | Out-Null
Add-Text $s 60 150 ($W-120) 70 "NodeConfigurator" 46 $true $cWhite $alignL | Out-Null
Add-Text $s 60 220 ($W-120) 50 "A Modular Extension Host for .NET MAUI Blazor Hybrid" 22 $false (RGB 200 215 235) $alignL | Out-Null
$pill = Add-Box $s $msoRoundRect 60 300 360 44 (RGB 255 255 255) (RGB 255 255 255) "Phase 3 - Runtime Plugin Isolation" 16 $true $bandF 0
$pill.Line.Visible = $msoFalse
Add-Text $s 60 380 ($W-120) 60 "Blazor Hybrid (.NET MAUI, .NET 10)  -  Razor Class Library extensions  -  in-memory pub/sub event bus  -  System.Text.Json persistence" 13 $false (RGB 190 205 225) $alignL | Out-Null

# ============================================================
# SLIDE 2 — JOURNEY OVERVIEW (timeline)
# ============================================================
$s = Add-Slide
Add-TitleBand $s "The Journey: From Shell to Independently Shippable Plugins"
$y = 210 ; $bw = 250 ; $bh = 130
$b1 = Add-Box $s $msoRoundRect 60 $y $bw $bh $greenF $greenL "Phase 1`nInitial Build`n(Demo Done)" 16 $true $cText 0
$b2 = Add-Box $s $msoRoundRect (60+$bw+55) $y $bw $bh $blueF $blueL "Phase 2`nUI Refactor`n(Demo Done)" 16 $true $cText 0
$b3 = Add-Box $s $msoRoundRect (60+2*($bw+55)) $y $bw $bh $orangeF $orangeL "Phase 3`nFull Extension Isolation`n(In Progress)" 16 $true $cText 0
Add-Arrow $s (60+$bw) ($y+$bh/2) (60+$bw+55) ($y+$bh/2) $grayL 2.5 $false | Out-Null
Add-Arrow $s (60+2*$bw+55) ($y+$bh/2) (60+2*$bw+2*55) ($y+$bh/2) $grayL 2.5 $false | Out-Null
Add-Text $s 60 150 ($W-120) 30 "Same requirements preserved at every step; each phase increases decoupling." 15 $false $cSub $alignL | Out-Null
Add-Text $s 60 370 ($W-120) 40 "This deck focuses on Phase 3: shipping and loading each extension independently at runtime." 15 $true $cTitle $alignL | Out-Null

# ============================================================
# SLIDE 3 — PHASE 1 & 2 SUMMARY (combined)
# ============================================================
$s = Add-Slide
Add-TitleBand $s "Phase 1 and 2 - Summary (Completed)"
$colW = 420
$h1 = Add-Box $s $msoRoundRect 40 80 $colW 40 $greenF $greenL "Phase 1 - Initial Build" 16 $true $cText 0
Add-Bullets $s 50 128 ($colW-10) 340 @(
 "Extensible shell - host loads multiple independent UI extensions",
 "Central Node extension - pick one computer as the central node",
 "Identity extension - None / GitHub / EntraID / PingID",
 "Mode extension - toggle Connected / Disconnected",
 "Single central-node rule - only one node central at a time",
 "Cross-extension validation - Connected requires EntraID",
 "Persistence to JSON + full state restore on startup",
 "Node navigation with aggregated details",
 "UI: extensions shown as separate sidebar tabs"
) 13 $cText | Out-Null

$h2 = Add-Box $s $msoRoundRect (40+$colW+20) 80 $colW 40 $blueF $blueL "Phase 2 - UI Refactor" 16 $true $cText 0
Add-Bullets $s (50+$colW+20) 128 ($colW-10) 340 @(
 "Per-node configuration - central + identity moved onto each node's page",
 "Single central-node rule enforced inline - others auto-update",
 "Conflict surfaced on the node - Connected-requires-EntraID shown in list",
 "Action-based saving - on Save / navigation / close",
 "All Phase 1 validation and persistence preserved",
 "No behavior lost - purely a clearer UX"
) 13 $cText | Out-Null

# ============================================================
# SLIDE 4 — PHASE 3 GOALS
# ============================================================
$s = Add-Slide
Add-TitleBand $s "Phase 3 - Goals: Independently Shippable Extensions"
Add-Text $s 40 78 ($W-80) 30 "Decouple the system so each extension is built, versioned, and loaded on its own." 15 $true $cTitle $alignL | Out-Null
$cardW = 285 ; $cardH = 200 ; $cy = 130
$c1 = Add-Box $s $msoRoundRect 40 $cy $cardW $cardH $blueF $blueL $null 0 $false $cText 0
Add-Text $s 55 145 ($cardW-30) 30 "Independent teams" 16 $true $blueL $alignL | Out-Null
Add-Bullets $s 55 180 ($cardW-30) 140 @("Each extension in its own repo/folder","Its own dependencies and version","No shared build") 13 $cText | Out-Null
$c2 = Add-Box $s $msoRoundRect (40+$cardW+22) $cy $cardW $cardH $orangeF $orangeL $null 0 $false $cText 0
Add-Text $s (55+$cardW+22) 145 ($cardW-30) 30 "Runtime loading" 16 $true $orangeL $alignL | Out-Null
Add-Bullets $s (55+$cardW+22) 180 ($cardW-30) 140 @("Host discovers plugins at startup","Loaded from C:\plugins\<id>\<version>","No compile-time references to plugins") 13 $cText | Out-Null
$c3 = Add-Box $s $msoRoundRect (40+2*($cardW+22)) $cy $cardW $cardH $purpleF $purpleL $null 0 $false $cText 0
Add-Text $s (55+2*($cardW+22)) 145 ($cardW-30) 30 "Version flexibility" 16 $true $purpleL $alignL | Out-Null
Add-Bullets $s (55+2*($cardW+22)) 180 ($cardW-30) 140 @("Swap extension sets/versions","Highest version auto-selected","No host recompile required") 13 $cText | Out-Null
Add-Text $s 40 355 ($W-80) 30 "Key idea: a thin, stable contract (Abstractions) + one AssemblyLoadContext per plugin." 15 $true $cTitle $alignL | Out-Null

# ============================================================
# SLIDE 5 — PHASE 3 ARCHITECTURE DIAGRAM (recreate ref image 2)
# ============================================================
$s = Add-Slide
Add-TitleBand $s "Phase 3 - Runtime Plugin Isolation (ALC per Plugin)"

# Host solution box (left)
$hx=30; $hy=95; $hw=225; $hh=300
Add-Box $s $msoRect $hx $hy $hw $hh $hostF $hostL $null 0 $false $cText 1.25 | Out-Null
Add-Text $s $hx ($hy+6) $hw 22 "Host Solution" 13 $true $cTitle $alignC | Out-Null
Add-Box $s $msoRect ($hx+15) ($hy+40) ($hw-30) 46 $cWhite $hostL "NodeConfigurator.Host" 11 $false $cText 1 | Out-Null
Add-Box $s $msoRect ($hx+15) ($hy+98) ($hw-30) 60 $cWhite $hostL "NodeConfigurator.Core`n(PluginLoader, PluginLoadContext)" 10 $false $cText 1 | Out-Null
$absShape = Add-Box $s $msoRect ($hx+15) ($hy+170) ($hw-30) 60 $cWhite $hostL "NodeConfigurator.Abstractions`n(NuGet)" 10 $false $cText 1

# Deployment folder box (right)
$dx=760; $dy=95; $dw=180; $dh=300
Add-Box $s $msoRect $dx $dy $dw $dh $hostF $hostL $null 0 $false $cText 1.25 | Out-Null
Add-Text $s $dx ($dy+6) $dw 34 "Plugin Deployment`nFolder: C:\plugins\" 11 $true $cTitle $alignC | Out-Null
Add-Box $s $msoRect ($dx+20) ($dy+55) ($dw-40) 44 $cWhite $hostL "identity\1.0.0" 11 $false $cText 1 | Out-Null
Add-Box $s $msoRect ($dx+20) ($dy+120) ($dw-40) 44 $cWhite $hostL "centralnode\1.0.0" 11 $false $cText 1 | Out-Null
Add-Box $s $msoRect ($dx+20) ($dy+185) ($dw-40) 44 $cWhite $hostL "mode\1.0.0" 11 $false $cText 1 | Out-Null

# Runtime loader arrow (top)
$la = Add-Box $s $msoRightArrow ($hx+$hw+8) 100 ($dx-($hx+$hw)-16) 40 $grayF $grayL $null 0 $false $cText 0.75
Add-Text $s ($hx+$hw+8) 78 ($dx-($hx+$hw)-16) 18 "Runtime Plugin Loader" 11 $true $cSub $alignC | Out-Null
Add-Text $s ($hx+$hw+8) 104 ($dx-($hx+$hw)-16) 32 "Discover -> Read manifest.json -> Select highest version -> Load" 10 $false $cText $alignC | Out-Null

# 3 ALC boxes (middle)
$alcY=175; $alcW=150; $alcH=150; $gap=20
$alcX1=290; $alcX2=$alcX1+$alcW+$gap; $alcX3=$alcX2+$alcW+$gap
foreach($cfg in @(@($alcX1,"Plugin:identity"),@($alcX2,"Plugin:centralnode"),@($alcX3,"Plugin:mode"))){
	$ax=$cfg[0]; $nm=$cfg[1]
	Add-Box $s $msoRect $ax $alcY $alcW $alcH $grayF $grayL $null 0 $false $cText 1 | Out-Null
	Add-Text $s $ax ($alcY+5) $alcW 30 ("AssemblyLoadContext:`n"+$nm) 9 $true $cTitle $alignC | Out-Null
	Add-Box $s $msoRect ($ax+12) ($alcY+42) ($alcW-24) 44 $cWhite $grayL "Plugin Entry Assembly" 9 $false $cText 0.75 | Out-Null
	Add-Box $s $msoRect ($ax+12) ($alcY+96) ($alcW-24) 44 $cWhite $grayL "Private Dependencies" 9 $false $cText 0.75 | Out-Null
	Add-Arrow $s ($dx) ($dy+80) ($ax+$alcW/2) $alcY $grayL 1.25 $false | Out-Null
}

# Event bus bottom bar
$busY=445
Add-Box $s $msoRect 290 $busY ($alcX3+$alcW-290) 34 (RGB 150 150 150) (RGB 110 110 110) "In-memory Pub/Sub Event Bus" 13 $true $cWhite 1 | Out-Null
Add-Arrow $s ($alcX1+$alcW/2) ($alcY+$alcH) ($alcX1+$alcW/2) $busY $grayL 1.25 $false | Out-Null
Add-Arrow $s ($alcX3+$alcW/2) ($alcY+$alcH) ($alcX3+$alcW/2) $busY $grayL 1.25 $false | Out-Null
Add-Arrow $s ($alcX1+$alcW/2) $busY ($absShape.Left+$absShape.Width/2) ($absShape.Top+$absShape.Height) $grayL 1.0 $true | Out-Null

# Callouts
$boundary = Add-Box $s $msoRoundRect 20 405 250 70 $cWhite $hostL "Boundary (shared): Abstractions + Blazor framework + System.Text.Json + JSInterop" 9.5 $false $cText 1
$boundary.Line.DashStyle = 4
$isolated = Add-Box $s $msoRoundRect ($alcX1) 340 ($alcW*2+$gap) 44 $cWhite $orangeL "Isolated (per plugin): Newtonsoft.Json, Markdig, etc." 10 $true $cText 1
$isolated.Line.DashStyle = 4

# ============================================================
# SLIDE 6 — HOW PLUGIN LOADING WORKS (lifecycle)
# ============================================================
$s = Add-Slide
Add-TitleBand $s "How Plugin Loading Works"
$steps = @("Discover","Read manifest.json","Select highest version","Create ALC","Resolve deps (.deps.json)","Load entry assembly","Instantiate IExtension","Register + render")
$sx=40; $sy=120; $sw=200; $sh=48; $vgap=22
for($i=0;$i -lt $steps.Count;$i++){
	$col = [int]($i/4); $row = $i%4
	$x = $sx + $col*($sw+120)
	$y = $sy + $row*($sh+$vgap)
	Add-Box $s $msoRoundRect $x $y $sw $sh $blueF $blueL ("$($i+1). "+$steps[$i]) 13 $true $cText 1 | Out-Null
	if($row -lt 3){ Add-Arrow $s ($x+$sw/2) ($y+$sh) ($x+$sw/2) ($y+$sh+$vgap) $blueL 1.5 $false | Out-Null }
}
# connect column 1 bottom to column 2 top
Add-Arrow $s ($sx+$sw) ($sy+$sh/2) ($sx+$sw+120) ($sy+$sh/2) $blueL 1.5 $false | Out-Null
Add-Bullets $s ($sx+2*($sw+120)-100) 130 320 300 @(
 "Each plugin -> its own PluginLoadContext (collectible ALC)",
 "Boundary assemblies resolve from the host (single type identity)",
 "Everything else loads from the plugin folder",
 "One bad plugin is logged and skipped (ContinueOnError)",
 "UI rendered via DynamicComponent(ComponentType)"
) 13 $cText | Out-Null

# ============================================================
# SLIDE 7 — THE BOUNDARY (thin waist)
# ============================================================
$s = Add-Slide
Add-TitleBand $s "The Thin Waist - Shared vs Isolated"
$half = 430
$shShared = Add-Box $s $msoRoundRect 40 100 $half 340 $greenF $greenL $null 0 $false $cText 0
Add-Text $s 40 110 $half 30 "SHARED (Boundary)" 17 $true $greenL $alignC | Out-Null
Add-Bullets $s 60 155 ($half-40) 270 @(
 "NodeConfigurator.Abstractions (the IExtension contract)",
 "Blazor component model (Microsoft.AspNetCore.Components*)",
 "System.Text.Json (JsonElement crosses the boundary)",
 "Microsoft.JSInterop",
 "DI + Logging abstractions",
 "Why: these types cross host <-> plugin, so identity must be unified"
) 13.5 $cText | Out-Null

$shIso = Add-Box $s $msoRoundRect (40+$half+20) 100 $half 340 $orangeF $orangeL $null 0 $false $cText 0
Add-Text $s (40+$half+20) 110 $half 30 "ISOLATED (per plugin)" 17 $true $orangeL $alignC | Out-Null
Add-Bullets $s (60+$half+20) 155 ($half-40) 270 @(
 "Newtonsoft.Json (Identity 12.0.3 vs CentralNode 13.0.3)",
 "Markdig (Identity 0.31.0 vs CentralNode 0.38.0)",
 "Any private helper/data libraries",
 "Loaded from the plugin folder via .deps.json",
 "Why: no such type appears on the contract surface",
 "Result: plugins version dependencies independently"
) 13.5 $cText | Out-Null

# ============================================================
# SLIDE 8 — EVENT BUS PUB/SUB (recreate ref image 1)
# ============================================================
$s = Add-Slide
Add-TitleBand $s "Event Bus - Publish / Subscribe Flow"

# Central hub
$hubX=400; $hubY=210; $hubW=180; $hubH=110
Add-Box $s $msoRoundRect $hubX $hubY $hubW $hubH $grayF (RGB 120 120 120) "Host Event Bus`n(in-memory)`nCentral Communication Hub" 12 $true $cText 1.5 | Out-Null

# Host UI (top-left, blue)
$ui = Add-Box $s $msoRoundRect 90 100 180 46 $blueF $blueL "Host UI" 13 $true $cText 1.25
Add-Arrow $s ($ui.Left+$ui.Width/2) ($ui.Top+$ui.Height) ($hubX+40) $hubY $blueL 1.75 $false | Out-Null
Add-Text $s 250 150 200 20 "Publish: NodeSelected" 10 $false $blueL $alignL | Out-Null

# Central Node Extension (top-right, green)
$cn = Add-Box $s $msoRoundRect 700 100 180 46 $greenF $greenL "Central Node Extension" 12 $true $cText 1.25
Add-Arrow $s ($cn.Left) ($cn.Top+$cn.Height) ($hubX+$hubW-40) $hubY $greenL 1.75 $false | Out-Null
Add-Text $s 520 150 190 20 "Publish: CentralNodeChanged" 10 $false $greenL $alignL | Out-Null

# Mode Extension (right, orange)
$md = Add-Box $s $msoRoundRect 720 235 160 46 $orangeF $orangeL "Mode Extension" 12 $true $cText 1.25
Add-Arrow $s ($md.Left) ($md.Top+$md.Height/2) ($hubX+$hubW) ($md.Top+$md.Height/2) $orangeL 1.75 $false | Out-Null
Add-Text $s 588 210 130 20 "Publish: ModeChanged" 10 $false $orangeL $alignL | Out-Null

# Identity Extension (bottom-right, purple)
$id = Add-Box $s $msoRoundRect 700 360 180 46 $purpleF $purpleL "Identity Extension" 12 $true $cText 1.25
Add-Arrow $s ($id.Left) ($id.Top) ($hubX+$hubW-30) ($hubY+$hubH) $purpleL 1.75 $false | Out-Null
Add-Text $s 590 330 150 20 "Subscribe: ModeChanged" 10 $false $purpleL $alignL | Out-Null
Add-Text $s 590 405 150 20 "Publish: ValidationResult" 10 $false $purpleL $alignL | Out-Null

# Persistence (left, tan)
$per = Add-Box $s $msoRoundRect 100 335 200 56 $tanF $tanL "Persistence (JSON)" 13 $true $cText 1.25
Add-Arrow $s ($hubX) ($hubY+$hubH-20) ($per.Left+$per.Width) ($per.Top+10) $tanL 1.75 $false | Out-Null
Add-Text $s 300 300 150 20 "Publish: Save" 10 $false $tanL $alignL | Out-Null
Add-Text $s 70 300 220 20 "Save -> Write JSON" 10 $false $cSub $alignL | Out-Null
Add-Text $s 70 400 240 34 "Startup -> Read JSON and Host Hydrates Extensions" 10 $false $cSub $alignL | Out-Null

# Validation rule callout
$vr = Add-Box $s $msoRoundRect 760 235 175 60 $yellowF $yellowL "Validation Rule: If Mode=Connected then Identity must be EntraID" 9.5 $false $cText 1
$vr.Line.DashStyle = 4
$vr.Top = 300; $vr.Left = 748; $vr.Width=190; $vr.Height=52

# Legend
$lg = Add-Box $s $msoRoundRect 40 460 400 62 $cWhite $grayL $null 0 $false $cText 1
Add-Text $s 55 465 380 18 "Legend" 12 $true $cTitle $alignL | Out-Null
Add-Text $s 55 486 380 16 "-> Publish: event to bus (Sender to Hub)" 11 $false $cText $alignL | Out-Null
Add-Text $s 55 503 380 16 "<- Subscribe: bus to handler (Hub to Receiver)" 11 $false $cText $alignL | Out-Null

# ============================================================
# SLIDE 9 — DEPENDENCY ISOLATION PROOF
# ============================================================
$s = Add-Slide
Add-TitleBand $s "Dependency Isolation - Proven"
Add-Text $s 40 78 ($W-80) 30 "Two plugins load different versions of the same libraries at the same time - no conflict." 15 $true $cTitle $alignL | Out-Null
# table
$tx=60; $ty=130; $rowH=54; $c0=200; $c1=280; $c2=280
$headers = @("","Newtonsoft.Json","Markdig")
$rows = @(
 @("Identity (ext.identity)","12.0.3","0.31.0"),
 @("CentralNode (ext.central)","13.0.3","0.38.0")
)
# header
Add-Box $s $msoRect $tx $ty $c0 $rowH $bandF $bandF "Plugin" 13 $true $cWhite 0.5 | Out-Null
Add-Box $s $msoRect ($tx+$c0) $ty $c1 $rowH $bandF $bandF "Newtonsoft.Json" 13 $true $cWhite 0.5 | Out-Null
Add-Box $s $msoRect ($tx+$c0+$c1) $ty $c2 $rowH $bandF $bandF "Markdig" 13 $true $cWhite 0.5 | Out-Null
for($r=0;$r -lt $rows.Count;$r++){
	$ry=$ty+($r+1)*$rowH
	$fill = if($r -eq 0){$blueF}else{$greenF}
	Add-Box $s $msoRect $tx $ry $c0 $rowH $fill $grayL $rows[$r][0] 12 $true $cText 0.5 | Out-Null
	Add-Box $s $msoRect ($tx+$c0) $ry $c1 $rowH $cWhite $grayL $rows[$r][1] 15 $true $cText 0.5 | Out-Null
	Add-Box $s $msoRect ($tx+$c0+$c1) $ry $c2 $rowH $cWhite $grayL $rows[$r][2] 15 $true $cText 0.5 | Out-Null
}
Add-Bullets $s 60 320 ($W-120) 180 @(
 "Each plugin resolves its packages from its own folder via .deps.json",
 "Loaded into its own ALC -> distinct assembly identities, no version clash",
 "Proof at startup logs assembly version + path + ALC name per plugin",
 "PublishTrimmed=false + a 'touch' call keep the DLLs in the publish output",
 "Deploy-Plugin.ps1 verifies deps.json, Newtonsoft.Json.dll, Markdig.dll are present"
) 14 $cText | Out-Null

# ============================================================
# SLIDE 10 — TECH STACK + STATUS
# ============================================================
$s = Add-Slide
Add-TitleBand $s "Tech Stack and Status"
$c1x=40; $c2x=500; $cw=420
Add-Box $s $msoRoundRect $c1x 90 $cw 180 $blueF $blueL $null 0 $false $cText 0 | Out-Null
Add-Text $s $c1x 100 $cw 26 "Tech Used" 16 $true $blueL $alignC | Out-Null
Add-Bullets $s ($c1x+20) 135 ($cw-40) 130 @(
 "Blazor Hybrid (.NET MAUI, .NET 10)",
 "Razor Class Libraries for extensions",
 "AssemblyLoadContext + AssemblyDependencyResolver",
 "In-memory pub/sub event bus",
 "System.Text.Json persistence"
) 13.5 $cText | Out-Null

Add-Box $s $msoRoundRect $c2x 90 $cw 180 $orangeF $orangeL $null 0 $false $cText 0 | Out-Null
Add-Text $s $c2x 100 $cw 26 "Phase 3 Status" 16 $true $orangeL $alignC | Out-Null
Add-Bullets $s ($c2x+20) 135 ($cw-40) 130 @(
 "Runtime discovery + version selection - working",
 "Per-plugin ALC isolation - working",
 "Newtonsoft.Json + Markdig isolation - proven",
 "Repeatable deploy + verify scripts - done"
) 13.5 $cText | Out-Null

Add-Box $s $msoRoundRect $c1x 290 ($cw*2+60) 180 $purpleF $purpleL $null 0 $false $cText 0 | Out-Null
Add-Text $s $c1x 300 ($cw*2+60) 26 "Next Steps" 16 $true $purpleL $alignC | Out-Null
Add-Bullets $s ($c1x+20) 335 ($cw*2+20) 130 @(
 "Plugin signing + manifest validation before load",
 "Optional build-time guard (no Host/Core references, no copy-local boundary DLLs)",
 "Hot reload / unload story (ALC is collectible today)",
 "Broaden isolation tests across more extensions and versions"
) 13.5 $cText | Out-Null

# Save
$pres.SaveAs($OutPath)
$pres.Close()
$app.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($pres) | Out-Null
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($app) | Out-Null
Write-Host "Saved: $OutPath"
