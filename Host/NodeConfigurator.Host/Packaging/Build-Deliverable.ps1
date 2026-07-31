# =============================================================================
# Build-Deliverable.ps1
# Assembles a manager-ready ZIP for NodeConfigurator: host source, extension
# repos, local NuGet (Abstractions), pre-published plugins, docs + diagrams,
# and the runtime helper scripts (Setup / Verify / Run-Host).
#
# This script ONLY packages artifacts. It never changes the plugin loader or UI.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\Packaging\Build-Deliverable.ps1
# =============================================================================

[CmdletBinding()]
param(
	[string]$OutputRoot             = ".\Packaging\out",
	[string]$DeliverableName        = "NodeConfigurator_Deliverable",
	[string]$Version                = "1.0.0",
	[string]$PluginsRoot            = "C:\plugins",
	[string]$LocalNugetPath         = "C:\LocalNuget",
	[string]$ExtensionReposRoot     = "C:\repos",
	[string]$DocsReportPath         = "",
	[string]$DiagramOutputFolderName = "Architecture_Diagrams"
)

$ErrorActionPreference = "Stop"

# ----------------------------- helpers ---------------------------------------
function Write-Step($m)  { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok($m)    { Write-Host "    [ok]   $m" -ForegroundColor Green }
function Write-Warn2($m) { Write-Host "    [warn] $m" -ForegroundColor Yellow }
function Fail($m)        { Write-Host "    [FAIL] $m" -ForegroundColor Red; throw $m }

# Junk that must never ship in the source folders.
$ExcludeDirs  = @("bin", "obj", ".vs", ".git", "TestResults")
$ExcludeFiles = @("*.user", "*.suo")

# Long-path prefix so deep staging paths (> 260 chars) work on Windows.
function ToLongPath([string]$p) {
	if ([string]::IsNullOrEmpty($p)) { return $p }
	if ($p.StartsWith("\\?\")) { return $p }
	if ($p.StartsWith("\\"))   { return "\\?\UNC\" + $p.Substring(2) }
	return "\\?\" + $p
}

# Long-path-safe directory create / file copy via .NET IO (PowerShell providers
# reject the \\?\ prefix for New-Item, so use System.IO directly).
function New-Dir([string]$path) {
	[void][System.IO.Directory]::CreateDirectory((ToLongPath $path))
}
function Copy-FileLP([string]$src, [string]$dst) {
	[System.IO.File]::Copy((ToLongPath $src), (ToLongPath $dst), $true)
}

# Robust, exclusion-aware recursive copy with directory pruning so it never
# descends into excluded folders (or into the deliverable output itself).
function Copy-Tree {
	param([string]$Source, [string]$Destination, [string]$SkipPrefix = "", [string[]]$ExcludeTopLevel = @())

	if (-not (Test-Path $Source)) { Fail "Source not found: $Source" }
	New-Dir $Destination

	$srcFull  = (Resolve-Path $Source).Path.TrimEnd('\')
	$dstFull  = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\')
	$skipFull = ""
	if ($SkipPrefix) { $skipFull = [System.IO.Path]::GetFullPath($SkipPrefix).TrimEnd('\') }

	# Manual BFS so we can prune excluded directories before descending.
	$stack = New-Object System.Collections.Generic.Stack[string]
	$stack.Push($srcFull)

	while ($stack.Count -gt 0) {
		$dir = $stack.Pop()

		foreach ($child in [System.IO.Directory]::GetDirectories($dir)) {
			$name = [System.IO.Path]::GetFileName($child)
			if ($ExcludeDirs -contains $name) { continue }
			# Prune folders that must only be excluded at the source root.
			if ($dir -eq $srcFull -and ($ExcludeTopLevel -contains $name)) { continue }
			if ($skipFull -and $child.TrimEnd('\').StartsWith($skipFull, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
			$rel = $child.Substring($srcFull.Length).TrimStart('\')
			New-Dir (Join-Path $dstFull $rel)
			$stack.Push($child)
		}

		foreach ($file in [System.IO.Directory]::GetFiles($dir)) {
			$fname = [System.IO.Path]::GetFileName($file)
			$skip = $false
			foreach ($pat in $ExcludeFiles) { if ($fname -like $pat) { $skip = $true; break } }
			if ($skip) { continue }
			$rel = $file.Substring($srcFull.Length).TrimStart('\')
			$target = Join-Path $dstFull $rel
			New-Dir (Split-Path $target -Parent)
			Copy-FileLP $file $target
		}
	}
}

# ----------------------------- layout ----------------------------------------
$HostRepoRoot = (Resolve-Path ".").Path
if (-not [System.IO.Path]::IsPathRooted($OutputRoot)) {
    $OutputRoot = Join-Path $HostRepoRoot $OutputRoot
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$stamp   = Get-Date -Format "yyyy-MM-dd"
$stageParent = Join-Path $OutputRoot "$($DeliverableName)_$($stamp)_$($Version)"
$root    = Join-Path $stageParent $DeliverableName          # folder that gets zipped
$zipPath = Join-Path $stageParent "$($DeliverableName)_$($stamp)_$($Version).zip"

Write-Step "NodeConfigurator deliverable builder"
Write-Host "    Host repo      : $HostRepoRoot"
Write-Host "    Staging folder : $root"
Write-Host ""

# Idempotent: clear any previous staging for this exact name/date/version.
# cmd rmdir handles deep (>260) paths reliably.
if (Test-Path $stageParent) { cmd /c "rmdir /s /q `"$stageParent`"" | Out-Null }
New-Dir $root

# ----------------------------- 1) host source --------------------------------
Write-Step "Copying host source"
$hostDest = Join-Path $root "Host\NodeConfigurator.Host"
# Exclude the stale in-repo 'extensions' folder: the canonical extension source
# ships under the top-level Extensions\ folder (from the separate plugin repos).
Copy-Tree -Source $HostRepoRoot -Destination $hostDest -SkipPrefix $OutputRoot -ExcludeTopLevel @("extensions")
# Never ship the build output of the packaging run itself.
$pkgOutInStage = Join-Path $hostDest "Packaging\out"
if (Test-Path $pkgOutInStage) { cmd /c "rmdir /s /q `"$pkgOutInStage`"" | Out-Null }
Write-Ok "Host source staged (junk excluded)."

# ----------------------------- 2) extension repos ----------------------------
Write-Step "Copying extension repos"
$extMap = @{
	"Extension.Identity"    = "Extension.Identity"
	"Extension.CentralNode" = "Extension.CentralNode"
	"Extension.Mode"        = "Extension.Mode"
}
foreach ($name in $extMap.Keys) {
	$src = Join-Path $ExtensionReposRoot $name
	if (-not (Test-Path $src)) { Fail "Extension repo missing: $src" }
	$dst = Join-Path $root ("Extensions\" + $extMap[$name])
	Copy-Tree -Source $src -Destination $dst
	Write-Ok "Staged $name"
}

# ----------------------------- 3) local nuget --------------------------------
Write-Step "Copying local NuGet (Abstractions)"
$nugetDest = Join-Path $root "LocalNuget"
New-Dir $nugetDest
if (-not (Test-Path $LocalNugetPath)) { Fail "LocalNuget path not found: $LocalNugetPath" }
$nupkgs = Get-ChildItem -Path $LocalNugetPath -Filter "NodeConfigurator.Abstractions.*.nupkg" -File -ErrorAction SilentlyContinue
if (-not $nupkgs -or $nupkgs.Count -eq 0) {
	Fail "No NodeConfigurator.Abstractions.*.nupkg found in $LocalNugetPath. Plugins cannot restore the contract without it."
}
$nupkgs | ForEach-Object { Copy-Item $_.FullName -Destination $nugetDest -Force }
Write-Ok "Copied $($nupkgs.Count) Abstractions package(s)."

# ----------------------------- 4) plugins ------------------------------------
Write-Step "Copying pre-published plugins and validating core files"
$pluginsDest = Join-Path $root "plugins"
New-Dir $pluginsDest
if (-not (Test-Path $PluginsRoot)) { Fail "PluginsRoot not found: $PluginsRoot" }

$expectedPlugins = @("identity", "centralnode", "mode")
foreach ($plugId in $expectedPlugins) {
	$pidSrc = Join-Path $PluginsRoot $plugId
	if (-not (Test-Path $pidSrc)) { Fail "Plugin folder missing: $pidSrc" }

	$versionDirs = Get-ChildItem -Path $pidSrc -Directory -ErrorAction SilentlyContinue
	if (-not $versionDirs -or $versionDirs.Count -eq 0) { Fail "No version folders under $pidSrc" }

	foreach ($vdir in $versionDirs) {
		# Validate required core files before copying.
		if (-not (Get-ChildItem $vdir.FullName -File -ErrorAction SilentlyContinue)) {
			Fail "Plugin version folder is empty: $($vdir.FullName)"
		}
		if (-not (Test-Path (Join-Path $vdir.FullName "manifest.json"))) {
			Fail "manifest.json missing in $($vdir.FullName)"
		}
		if (-not (Get-ChildItem $vdir.FullName -Filter "*.deps.json" -File)) {
			Fail "*.deps.json missing in $($vdir.FullName)"
		}
		# Entry dll: read manifest.entryAssembly and confirm it exists.
		$manifest = Get-Content (Join-Path $vdir.FullName "manifest.json") -Raw | ConvertFrom-Json
		$entryDll = $manifest.entryAssembly
		if ([string]::IsNullOrWhiteSpace($entryDll) -or -not (Test-Path (Join-Path $vdir.FullName $entryDll))) {
			Fail "Entry assembly '$entryDll' missing in $($vdir.FullName)"
		}

		$dst = Join-Path $pluginsDest (Join-Path $plugId $vdir.Name)
		Copy-Tree -Source $vdir.FullName -Destination $dst
		Write-Ok "$plugId\$($vdir.Name) validated + staged (entry: $entryDll)"
	}
}

# ----------------------------- 5) docs: diagrams + report --------------------
Write-Step "Downloading architecture diagrams"
$docsDest = Join-Path $root "Docs"
$diagDest = Join-Path $docsDest $DiagramOutputFolderName
New-Dir $diagDest

$diagrams = @(
	@{ Url = "https://userdata-d7b62b.stack.tryrelevance.com/conversation/files/4a44c04b-8837-44df-87c4-f1ac9b314216.png"; Name = "phase1.png" },
	@{ Url = "https://userdata-d7b62b.stack.tryrelevance.com/conversation/files/69046d28-e2bb-4998-95fe-514fa5dc150e.png"; Name = "phase2.png" },
	@{ Url = "https://userdata-d7b62b.stack.tryrelevance.com/conversation/files/78f5b63b-1c86-4195-9d2f-900d42f1cf44.png"; Name = "phase3.png" },
	@{ Url = "https://userdata-d7b62b.stack.tryrelevance.com/conversation/files/ea8c6f92-3f74-4965-8b8f-f5fdf8ab5e9b.png"; Name = "eventbus.png" }
)
foreach ($d in $diagrams) {
	try {
		Invoke-WebRequest -Uri $d.Url -OutFile (Join-Path $diagDest $d.Name) -UseBasicParsing -TimeoutSec 60
		Write-Ok "Downloaded $($d.Name)"
	}
	catch {
		Write-Warn2 "Could not download $($d.Name): $($_.Exception.Message)"
	}
}

Write-Step "Copying complete report (optional)"
if ($DocsReportPath -and (Test-Path $DocsReportPath)) {
	Copy-Item $DocsReportPath -Destination (Join-Path $docsDest "NodeConfigurator_Complete_Report.docx") -Force
	Write-Ok "Report copied."
}
else {
	Write-Warn2 "DocsReportPath not provided or file missing. Skipping NodeConfigurator_Complete_Report.docx."
}

# ----------------------------- 6) README_RUNME_FIRST.md ----------------------
Write-Step "Generating README_RUNME_FIRST.md"

$howToRun = @'
# How to run this ZIP

You need: Windows, the .NET 10 SDK, and (to run the host) the .NET MAUI workload.

1. **Unzip** this archive to a working folder.
2. Open PowerShell in the unzipped `NodeConfigurator_Deliverable\` folder and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Setup.ps1
   ```
   This copies the pre-published plugins to `C:\plugins` and registers the local
   NuGet feed (`.\LocalNuget`) so the extension source can restore `NodeConfigurator.Abstractions`.
3. Verify the plugins are in place:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Verify.ps1
   ```
4. Run the host:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Run-Host.ps1
   ```
   or open `Host\NodeConfigurator.Host\NodeConfigurator.Host.slnx` in Visual Studio and press **F5**.

> Plugins are expected at `C:\plugins`. `Setup.ps1` puts them there.
> Architecture diagrams and the full report (if included) are under `Docs\`.

## What's in this ZIP

```
NodeConfigurator_Deliverable\
+-- README_RUNME_FIRST.md   this file (how to run + full architecture reference)
+-- Setup.ps1               copies plugins to C:\plugins + registers local NuGet feed
+-- Verify.ps1              validates the deployed plugins (manifest/deps/entry dll)
+-- Run-Host.ps1            runs the host (dotnet run) or points you to the solution
+-- Publish-All.ps1         (optional) re-publishes all extension repos to C:\plugins
+-- Host\
|   +-- NodeConfigurator.Host\   full host solution source:
|       +-- NodeConfigurator.Host\          MAUI Blazor Hybrid app (shell + rendering)
|       +-- NodeConfigurator.Core\          plugin infra (PluginLoader, PluginLoadContext, event bus, persistence)
|       +-- NodeConfigurator.Abstractions\  the shared IExtension contract (packed as NuGet)
+-- Extensions\             independent plugin source (one folder per team/repo)
|   +-- Extension.Identity\      Newtonsoft.Json 12 + Markdig 0.31 (isolation demo)
|   +-- Extension.CentralNode\   Newtonsoft.Json 13 + Markdig 0.38 (isolation demo)
|   +-- Extension.Mode\
+-- LocalNuget\             NodeConfigurator.Abstractions.*.nupkg (contract package)
+-- plugins\                pre-published, ready-to-run plugin output (<id>\<version>\)
+-- Docs\                   architecture diagrams + full report (if provided)
```

**To understand the code, start here:**
1. Read the architecture reference below (this file) and `Docs\Architecture_Diagrams\phase3.png`.
2. Host entry point + DI: `Host\NodeConfigurator.Host\NodeConfigurator.Host\`.
3. The plugin engine: `Host\NodeConfigurator.Host\NodeConfigurator.Core\Plugins\` (`PluginLoader.cs`, `PluginLoadContext.cs`).
4. The contract every plugin implements: `Host\NodeConfigurator.Host\NodeConfigurator.Abstractions\`.
5. Example plugin implementations: `Extensions\Extension.Identity\`, `Extensions\Extension.CentralNode\`, `Extensions\Extension.Mode\`.

---

'@

# The verbatim base README follows the short header above.
$baseReadme = @'
# NodeConfigurator â€” Runtime Plugin Architecture for .NET MAUI Blazor Hybrid

**Overview**

NodeConfigurator is a .NET MAUI Blazor Hybrid application that hosts UI **extensions** (plugins)
which are built, versioned, and shipped **independently** by separate teams. The host discovers
plugins on disk at startup, loads each one into its **own isolated `AssemblyLoadContext` (ALC)**,
and renders each plugin''s Razor UI inside the host shell.

The problem this solves:

- **Independent delivery** â€” teams build plugins in their own repos and deploy them to a shared
  plugins folder without recompiling or redeploying the host.
- **Dependency isolation** â€” two plugins can depend on *different versions* of the same library
  (proven with Newtonsoft.Json 12 vs 13) and coexist in one process with no conflicts.
- **A minimal, stable contract** â€” plugins only reference the `NodeConfigurator.Abstractions`
  NuGet package (the `IExtension` contract). The host and plugins never share their internals.

---

**Key Features**

- **Runtime discovery** â€” plugins are found from `appsettings.json` (`Plugins:Paths` and
  `Plugins:PluginRoots`). Drop a new plugin folder under a configured root and it loads on next start.
- **Version selection** â€” when the same plugin id appears in multiple version folders, the host
  automatically selects the **highest** version.
- **Per-plugin ALC isolation** â€” each plugin gets its own collectible `PluginLoadContext`, so
  internal dependencies are private to the plugin.
- **Minimal boundary (thin waist)** â€” only the assemblies whose *types cross the hostâ†”plugin
  boundary* are shared; everything else is isolated.
- **Multi-team separation** â€” plugins are separate repos, separate build pipelines, separate
  deployment artifacts.
- **Fault tolerance** â€” one bad plugin is logged and skipped; it never crashes the host
  (`Plugins:ContinueOnError`, default `true`).

---

**Repo / Folder Layout**

Host solution:

```
C:\...\NodeConfigurator.Host\
â”œâ”€â”€ NodeConfigurator.Host.slnx
â”œâ”€â”€ NodeConfigurator.Host\               # MAUI Blazor Hybrid app (shell + rendering)
â”œâ”€â”€ NodeConfigurator.Core\               # Plugin infrastructure
â”‚   â””â”€â”€ Plugins\
â”‚       â”œâ”€â”€ PluginLoader.cs              # discovery, version selection, load orchestration
â”‚       â”œâ”€â”€ PluginLoadContext.cs         # per-plugin AssemblyLoadContext + boundary rules
â”‚       â”œâ”€â”€ PluginManifest.cs            # manifest.json model + reader/validator
â”‚       â”œâ”€â”€ PluginOptions.cs             # "Plugins" config section binding
â”‚       â””â”€â”€ PluginExtensionRegistry.cs   # registry of loaded IExtension instances
â””â”€â”€ NodeConfigurator.Abstractions\       # The contract (published as a NuGet package)

```
The **Abstractions** package is published to a local NuGet feed:

```
C:\LocalNuget\    # NodeConfigurator.Abstractions.<version>.nupkg lives here

```
Plugin repos (independent, per team):

```
C:\repos\Extension.CentralNode\
C:\repos\Extension.Identity\
C:\repos\Extension.Mode\

```
Deployment layout (`C:\plugins\<pluginId>\<version>\`):

```
C:\plugins\
â”œâ”€â”€ centralnode\
â”‚   â””â”€â”€ 1.0.0\
â”‚       â”œâ”€â”€ manifest.json
â”‚       â”œâ”€â”€ NodeConfigurator.Extensions.CentralNode.dll
â”‚       â”œâ”€â”€ NodeConfigurator.Extensions.CentralNode.deps.json
â”‚       â”œâ”€â”€ Newtonsoft.Json.dll            # 13.0.3 (isolated)
â”‚       â””â”€â”€ wwwroot\                        # optional static assets
â”œâ”€â”€ identity\
â”‚   â””â”€â”€ 1.0.0\
â”‚       â”œâ”€â”€ manifest.json
â”‚       â”œâ”€â”€ NodeConfigurator.Extensions.Identity.dll
â”‚       â”œâ”€â”€ NodeConfigurator.Extensions.Identity.deps.json
â”‚       â””â”€â”€ Newtonsoft.Json.dll            # 12.0.3 (isolated)
â””â”€â”€ mode\
	â””â”€â”€ 1.0.0\
		â”œâ”€â”€ manifest.json
		â””â”€â”€ NodeConfigurator.Extensions.Mode.dll

```
---

**Quickstart**

*Run the host:*

1. Ensure the .NET 10 SDK and the MAUI workload are installed.
2. Build and run `NodeConfigurator.Host`.
3. On startup the host reads the `Plugins` config section, discovers plugins, loads them, and
   renders each plugin''s tab/UI.

*Build & deploy a plugin:*

1. In the plugin repo, reference the `NodeConfigurator.Abstractions` NuGet package (from
   `C:\LocalNuget`). Do **not** reference the host or core.
2. `dotnet publish` the plugin.
3. Copy the publish output into `C:\plugins\<pluginId>\<version>\` and make sure a
   `manifest.json` sits at the root of that folder (see the deployment script in
   [docs/Architecture-Report.md](docs/Architecture-Report.md)).
4. Confirm the folder contains: the entry `.dll`, its `.deps.json`, all private dependency DLLs,
   and (optionally) a `wwwroot\` folder.

*Required paths:*

- `NodeConfigurator.Abstractions` NuGet feed: `C:\LocalNuget`
- Plugin deployment root: `C:\plugins\<pluginId>\<version>\`
- Host config: `appsettings.json` under `NodeConfigurator.Host`

---

**How Plugin Loading Works (high level)**

1. **Discover** â€” `PluginLoader` collects candidate folders from `Plugins:Paths` (explicit) and by
   scanning `Plugins:PluginRoots` (flat `<root>\<name>` or versioned `<root>\<name>\<version>`).
2. **Parse manifest** â€” each candidate must have a `manifest.json`; it is read and validated by
   `PluginManifestReader`.
3. **Select version** â€” duplicate plugin ids are collapsed to the **highest version**
   (explicit path wins an exact-version tie).
4. **Isolate** â€” a new `PluginLoadContext` (a collectible `AssemblyLoadContext`) is created per
   plugin.
5. **Load & instantiate** â€” the entry assembly is loaded, the `IExtension` `entryType` is
   instantiated via reflection.
6. **Register & render** â€” the `IExtension` instance is placed in the extension registry
   (`PluginExtensionRegistry`) and its `ComponentType` is rendered by the host using Blazor''s
   `DynamicComponent`.

---

**Configuration: `appsettings.json`**

The `Plugins` section binds to `PluginOptions`.

Explicit paths only:

```json
{
  "Plugins": {
	"Paths": [
	  "C:/plugins/identity/1.0.0",
	  "C:/plugins/mode/1.0.0",
	  "C:/plugins/centralnode/1.0.0"
	],
	"PluginRoots": [],
	"ContinueOnError": true,
	"VerboseLogging": false
  }
}

```
Discovery roots (drop-in, no config edit for new plugins):

```json
{
  "Plugins": {
	"Paths": [],
	"PluginRoots": [ "C:/plugins" ],
	"ContinueOnError": true,
	"VerboseLogging": true
  }
}

```
Both can be combined. `Paths` and discovered folders are merged; duplicates by folder are removed,
and duplicate plugin ids are resolved to the highest version.

Example `manifest.json` (one per plugin folder):

```json
{
  "id": "ext.identity",
  "displayName": "Identity",
  "version": "1.0.0",
  "entryAssembly": "NodeConfigurator.Extensions.Identity.dll",
  "entryType": "NodeConfigurator.Extensions.Identity.IdentityExtension",
  "hasStaticAssets": false,
  "preloadAssemblies": []
}

```
---

**Troubleshooting**

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `Plugin folder does not exist` / `is empty` warning | Path in `Plugins:Paths` is wrong or the deploy didn''t copy files | Verify the deployed folder and path; check the deployment step |
| `Plugin manifest not found` | No `manifest.json` at the plugin folder root | Ensure `manifest.json` is published to the folder root |
| Manifest deserialization / validation error | Malformed JSON or missing required fields (`id`, `displayName`, `version`, `entryAssembly`, `entryType`) | Fix the manifest against the example above |
| `InvalidCastException` when host uses the plugin `IExtension` | Plugin shipped its own copy of a **boundary** assembly (Abstractions, System.Text.Json, Blazor, JSInterop, DI/Logging abstractions) | Reference these as framework/package references so they are **not** copied into the plugin output; let the host provide them |
| `FileNotFoundException` / `TypeLoadException` for a plugin dependency | A private dependency (or its `.deps.json`) was not deployed | Publish the plugin so all private DLLs and the `.deps.json` are present in the folder |
| Wrong plugin version loads | Multiple version folders present | Highest version wins; check the "Multiple versions ... using vX" log |
| File lock / "in use" on re-deploy | Host still running and holding the plugin DLL | Stop the host before overwriting (current model loads at startup â€” see update strategy in the report) |
| Static assets (CSS/JS) 404 | `hasStaticAssets` false or `wwwroot` not deployed | Set `hasStaticAssets: true` and deploy the `wwwroot` folder |

Set `"VerboseLogging": true` to trace discovery, manifest reads, version selection, and per-plugin
load decisions.

---

**Security Notes**

Loading a plugin executes its code **in-process with full trust**. There is no sandbox.

- Only deploy plugins from **trusted teams / pipelines**.
- Prefer **signed assemblies** and verify signatures before deployment.
- **Validate the manifest** and restrict plugin roots to controlled folders with proper file-system
  ACLs (so untrusted processes can''t drop DLLs into `C:\plugins`).
- Treat the plugins folder as a privileged deployment target in your CI/CD.
- See the "Future improvements" section of the architecture report for signing/validation plans.

---

**FAQ**

**Can UI libraries be isolated per plugin?**
Partially. The Blazor framework and the component model (`Microsoft.AspNetCore.Components*`) must be
**shared** so plugin components render inside the host renderer. Full third-party UI component
frameworks are practically shared (not safely isolated across versions). Helper libraries and
per-plugin CSS/JS **can** be isolated. See the UI isolation tiers in the report.

**What is shared (the boundary)?**
`NodeConfigurator.Abstractions`, `System.Text.Json`, `Microsoft.JSInterop`,
`Microsoft.Extensions.DependencyInjection.Abstractions`,
`Microsoft.Extensions.Logging.Abstractions`, and all `Microsoft.AspNetCore.Components*` assemblies,
plus the base runtime (handled automatically by the CLR).

**What is isolated?**
Everything else the plugin ships â€” e.g. Newtonsoft.Json, `Microsoft.Extensions.Http`, and other
internal dependencies. These load from the plugin''s own folder.

**Why per-plugin ALC?**
So each plugin can version its private dependencies independently and be unloaded/reloaded
(the contexts are collectible), while still sharing a single type identity for boundary types.

**Is the contract version-gated?**
No. `IExtension` in Abstractions is stable and never version-gated at runtime.

---

**Runtime Flow Overview**

A very practical view of what happens from launch to persistence:

1. **Startup** â€” the MAUI Blazor Hybrid host boots and builds its DI container.
2. **Plugin load** â€” `PluginLoader.LoadAll()` discovers, version-selects, and loads each plugin into
   its own `PluginLoadContext`, then instantiates each `IExtension` and puts it in the extension
   registry (`PluginExtensionRegistry`).
3. **DI** â€” the host''s shared singletons (`IEventBus`, `ISharedStateStore`, `ISaveCoordinator`,
   `INavigationService`, the node list) are composed into a single `IExtensionContext`.
4. **Initialize & hydrate** â€” `AppInitializer.InitializeAsync()` loads the saved `AppSnapshot`,
   then for each extension calls `IExtension.InitializeAsync(context)` followed by
   `IExtension.HydrateAsync(savedConfig)` (the per-extension `JsonElement`, or `null` if none).
5. **UI render** â€” the host renders each extension''s `IExtension.ComponentType` with Blazor''s
   `DynamicComponent`; the active node/tab is restored from the snapshot.
6. **Events** â€” user actions publish messages on the shared `IEventBus`; extensions that subscribed
   during `InitializeAsync` react (and may publish further messages).
7. **Persistence** â€” a save is triggered (e.g. an extension publishes `"{id}.save"` on navigate-away,
   or `ISaveCoordinator.RequestSave/SaveNow` is called). `SaveCoordinator` calls
   `IExtension.SerializeConfig()` on every extension and writes one `AppSnapshot` via `IStateStore`.

---

**Event Bus Quickstart**

The bus is `IEventBus` (host singleton, implemented by `InMemoryEventBus`). Plugins get it through
`IExtensionContext.Bus`. A `BusMessage` is `record BusMessage(string Topic, string SourceId, JsonElement Payload)`.

*Subscribe in `InitializeAsync` and keep the token to unsubscribe:*

```csharp
public sealed class IdentityExtension : IExtension, IDisposable
{
	private IDisposable? _subscription;
	private IExtensionContext _context = default!;

	public Task InitializeAsync(IExtensionContext context)
	{
		_context = context;

		// Subscribe returns an IDisposable subscription token.
		_subscription = context.Bus.Subscribe("node.selected", OnNodeSelected);
		return Task.CompletedTask;
	}

	private void OnNodeSelected(BusMessage message)
	{
		// Payload is a System.Text.Json JsonElement â€” read it directly.
		var nodeId = message.Payload.GetProperty("nodeId").GetString();
		// ...update internal state...
	}

	// Dispose the token to unsubscribe (bus removes the handler).
	public void Dispose() => _subscription?.Dispose();
}

```
*Publish from a component (build the `JsonElement` payload with `System.Text.Json`):*

```csharp
// Inside a Razor component or extension method.
[Inject] public IExtensionContext Context { get; set; } = default!;

private void PublishIdentityUpdated(string nodeId, string displayName)
{
	// Serialize an anonymous object, then parse to a JsonElement for the payload.
	var payload = JsonSerializer.SerializeToElement(new { nodeId, displayName });

	Context.Bus.Publish(new BusMessage(
		Topic: "identity.updated",
		SourceId: "ext.identity",
		Payload: payload));
}

```
*Handle a `JsonElement` payload defensively:*

```csharp
private void OnIdentityUpdated(BusMessage message)
{
	if (message.Payload.ValueKind == JsonValueKind.Object &&
		message.Payload.TryGetProperty("nodeId", out var nodeIdElement))
	{
		var nodeId = nodeIdElement.GetString();
		// ...react...
	}
}

```
> UI note: `InMemoryEventBus` invokes handlers **synchronously on the publishing thread**. A
> component that updates its UI from a handler must marshal to Blazor''s dispatcher, e.g.
> `await InvokeAsync(StateHasChanged);`.

---

**Debugging**

*Verify bus traffic:*

- The bus itself (`InMemoryEventBus`) does not log by default. To trace traffic, publish/subscribe
  through your extension code where you own an `ILogger`, and log the `Topic`, `SourceId`, and
  `Payload.GetRawText()` on publish and on receipt.
- Confirm a subscription is active by checking your extension''s `InitializeAsync` ran (see the
  plugin-load logs from `PluginLoader`: `Loaded plugin ''<id>'' v<version> ...`).
- Common gotcha: if nothing reacts, the **topic strings must match exactly** (they are plain
  strings, case-sensitive) and the publisher must run after the subscriber''s `InitializeAsync`.

*Verify config persistence:*

- State is a single JSON file written by `JsonStateStore` (path is provided to its constructor by
  host startup â€” implementation-specific, typically under the app data folder).
- The file deserializes to an `AppSnapshot`: `Shell`, `Nodes`, and `Extensions` (a map of
  `extensionId â†’ { Version, Config }`).
- Each extension''s blob lives under `Extensions["<your.extension.id>"].Config`. If your state isn''t
  restored, confirm the key matches `IExtension.Id` and that `SerializeConfig()` produced a valid
  `JsonElement`.
- Writes are atomic (a `.tmp` file is written then moved over the real file), so a partially written
  file should never be observed.

---

**Dependency Isolation Test (Newtonsoft.Json + Markdig)**

An automated, repeatable test proves that two plugins can load **different versions** of the same
libraries simultaneously â€” each from its own `PluginLoadContext` (ALC).

*What it proves:* the Identity and CentralNode plugins each load their **own** copies of
`Newtonsoft.Json` **and** `Markdig`, at different versions, with no conflict, because these are
**not** boundary assemblies (they resolve from each plugin''s folder via its `.deps.json`).

*Exact versions used:*

| Plugin | Newtonsoft.Json | Markdig |
| --- | --- | --- |
| Identity (`ext.identity`) | 12.0.3 | 0.31.0 |
| CentralNode (`ext.central`) | 13.0.3 | 0.38.0 |

*Deploy both (PowerShell):*

```powershell
# From each plugin repo root:
cd C:\repos\Extension.Identity
.\Deploy-Plugin.ps1 -PluginId identity -Version 1.0.0 -PluginsRoot C:\plugins

cd C:\repos\Extension.CentralNode
.\Deploy-Plugin.ps1 -PluginId centralnode -Version 1.0.0 -PluginsRoot C:\plugins

```
Each script publishes (`dotnet publish -c Release`), cleans the destination, copies `manifest.json`
(and `wwwroot`), and **verifies** that `*.deps.json`, `Newtonsoft.Json.dll`, and `Markdig.dll` are
present â€” failing loudly if any are missing.

*How to verify from logs:* each plugin runs an isolation smoke test at `InitializeAsync`. Logging is
on in DEBUG builds, or in any build when `NODECONFIG_ISOLATION_LOG=1`. Run the host and look for:

```
[isolation][ext.identity] Newtonsoft.Json v12.0.0.0 | ALC=Plugin:ext.identity | C:\plugins\identity\1.0.0\Newtonsoft.Json.dll
[isolation][ext.identity] Markdig v0.31.0.0 | ALC=Plugin:ext.identity | C:\plugins\identity\1.0.0\Markdig.dll
[isolation][ext.central] Newtonsoft.Json v13.0.0.0 | ALC=Plugin:ext.central | C:\plugins\centralnode\1.0.0\Newtonsoft.Json.dll
[isolation][ext.central] Markdig v0.38.0.0 | ALC=Plugin:ext.central | C:\plugins\centralnode\1.0.0\Markdig.dll

```
Different versions, different ALC names, and paths under each plugin''s own folder = isolation proven.

*Troubleshooting â€” DLLs missing from the plugin folder:*

- Confirm `<PublishTrimmed>false</PublishTrimmed>` is set in the plugin `.csproj` (trimming can drop
  seemingly "unused" dependencies).
- Confirm the "touch" method (`IsolationSmokeTest.Run`) is called from `InitializeAsync` and
  references `Newtonsoft.Json.JsonConvert` and `Markdig.Markdown.ToHtml` â€” this keeps the assemblies
  as real, used dependencies.
- Keep `Newtonsoft.Json` and `Markdig` as **normal** `PackageReference` (do **not** set
  `PrivateAssets=all` or `ExcludeAssets=runtime`, and do not treat them as framework references).
- Re-run `Deploy-Plugin.ps1`; it fails with a clear message listing whatever is missing.

---

For the deep technical design, lifecycle details, ALC internals, the dependency-isolation proof,
UI isolation tiers, deployment pipeline, the Event Bus flow, the Configuration & Persistence
flow, and future work, see [docs/Architecture-Report.md](docs/Architecture-Report.md).
'@

Set-Content -Path (Join-Path $root "README_RUNME_FIRST.md") -Value ($howToRun + $baseReadme) -Encoding UTF8
Write-Ok "README_RUNME_FIRST.md written."

# ----------------------------- 7) runtime scripts ----------------------------
Write-Step "Generating Setup.ps1 / Verify.ps1 / Run-Host.ps1"

$setupPs1 = @'
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
'@

$verifyPs1 = @'
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
'@

$runHostPs1 = @'
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
'@

$publishAllPs1 = @'
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
'@

Set-Content -Path (Join-Path $root "Setup.ps1")       -Value $setupPs1      -Encoding UTF8
Set-Content -Path (Join-Path $root "Verify.ps1")      -Value $verifyPs1     -Encoding UTF8
Set-Content -Path (Join-Path $root "Run-Host.ps1")    -Value $runHostPs1    -Encoding UTF8
Set-Content -Path (Join-Path $root "Publish-All.ps1") -Value $publishAllPs1 -Encoding UTF8
Write-Ok "Runtime scripts written."

# ----------------------------- 8) zip ----------------------------------------
Write-Step "Creating ZIP"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
# Use .NET ZipFile for reliable long-path support (Compress-Archive can trip on >260 chars).
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory((ToLongPath $root), (ToLongPath $zipPath), [System.IO.Compression.CompressionLevel]::Optimal, $true)
Write-Ok "ZIP created."

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Green
Write-Host " Deliverable ready" -ForegroundColor Green
Write-Host "   Staging : $root" -ForegroundColor Green
Write-Host "   ZIP     : $zipPath" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green

