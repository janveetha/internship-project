using System.Reflection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Core.Plugins;

/// <summary>
/// Represents a successfully loaded plugin with its metadata and instance.
/// </summary>
public sealed class LoadedPlugin
{
    /// <summary>The parsed manifest.</summary>
    public required PluginManifest Manifest { get; init; }

    /// <summary>The AssemblyLoadContext used to load this plugin.</summary>
    public required PluginLoadContext LoadContext { get; init; }

    /// <summary>The loaded entry assembly.</summary>
    public required Assembly Assembly { get; init; }

    /// <summary>The instantiated IExtension implementation.</summary>
    public required IExtension Extension { get; init; }
}

/// <summary>
/// Represents a plugin that failed to load, with diagnostic information.
/// </summary>
public sealed class FailedPlugin
{
    /// <summary>The plugin folder path that failed to load.</summary>
    public required string PluginPath { get; init; }

    /// <summary>The manifest, if it was successfully parsed before failure.</summary>
    public PluginManifest? Manifest { get; init; }

    /// <summary>The reason for the failure.</summary>
    public required string Reason { get; init; }

    /// <summary>The exception that caused the failure, if any.</summary>
    public Exception? Exception { get; init; }
}

/// <summary>
/// Result of the plugin loading operation.
/// </summary>
public sealed class PluginLoadResult
{
    /// <summary>Successfully loaded plugins.</summary>
    public List<LoadedPlugin> Loaded { get; } = new();

    /// <summary>Plugins that failed to load due to a genuine error (bad DLL, reflection, missing manifest, etc.).</summary>
    public List<FailedPlugin> Failed { get; } = new();

    /// <summary>True if no configured plugin failed to load.</summary>
    public bool AllSucceeded => Failed.Count == 0;
}

/// <summary>
/// Discovers, validates, loads, and instantiates plugins from configured folders.
/// </summary>
/// <remarks>
/// <para>
/// The loader performs these steps for each configured plugin path:
/// 1. Read and validate the manifest.json
/// 2. Create an isolated AssemblyLoadContext
/// 3. Load the entry assembly
/// 4. Instantiate the IExtension type
/// </para>
/// <para>
/// By default, failures are logged and skipped (one bad plugin doesn't crash the host).
/// Set <see cref="PluginOptions.ContinueOnError"/> to false to fail fast.
/// </para>
/// </remarks>
public sealed class PluginLoader
{
    private readonly PluginOptions _options;
    private readonly ILogger<PluginLoader> _logger;

    public PluginLoader(IOptions<PluginOptions> options, ILogger<PluginLoader> logger)
    {
        _options = options.Value;
        _logger = logger;
    }

    /// <summary>
    /// Loads all plugins from the configured paths.
    /// </summary>
    /// <returns>A result containing loaded plugins and any failures.</returns>
    public PluginLoadResult LoadAll()
    {
        var result = new PluginLoadResult();

        if (_options.Paths.Count == 0 && _options.PluginRoots.Count == 0)
        {
            _logger.LogInformation(
                "No plugin sources configured (Plugins:Paths and Plugins:PluginRoots are both empty).");
            return result;
        }

        _logger.LogInformation(
            "Loading plugins from {PathCount} explicit path(s) and {RootCount} discovery root(s)",
            _options.Paths.Count,
            _options.PluginRoots.Count);

        // Phase 1: gather candidate plugin folders from the explicit Paths and by
        // scanning each PluginRoots entry. De-duplicated by normalized folder path so
        // overlapping sources never load the same folder twice.
        var candidates = CollectCandidateFolders(result);

        // Phase 2: read each candidate's manifest. A folder that looks like a plugin but
        // has a missing/invalid manifest is recorded as a failure (never a crash).
        var parsed = ReadCandidateManifests(candidates, result);

        // Phase 3: when the same plugin id appears more than once (e.g. two versioned
        // folders under a root), keep the HIGHEST version and log the ones dropped.
        var selected = SelectHighestVersionPerId(parsed);

        // Phase 4: load each winner using the existing per-plugin PluginLoadContext
        // isolation model (the thin shared-contract waist is preserved).
        foreach (var candidate in selected)
        {
            LoadCandidate(result, candidate);
        }

        LogFinalSummary(result);

        return result;
    }

    /// <summary>Identifies where a candidate plugin folder came from.</summary>
    private enum PluginSource
    {
        /// <summary>An explicit folder listed in <see cref="PluginOptions.Paths"/>.</summary>
        Explicit,

        /// <summary>A folder found by scanning a <see cref="PluginOptions.PluginRoots"/> entry.</summary>
        Discovered
    }

    /// <summary>A candidate plugin folder to examine, plus where it came from.</summary>
    private sealed record PluginCandidate(string FolderPath, PluginSource Source);

    /// <summary>A candidate whose manifest has been read successfully.</summary>
    private sealed record ParsedCandidate(PluginCandidate Folder, PluginManifest Manifest);

    /// <summary>
    /// Phase 1. Builds the de-duplicated set of candidate plugin folders from both the
    /// explicit <see cref="PluginOptions.Paths"/> and the scanned
    /// <see cref="PluginOptions.PluginRoots"/>. Explicit folders that are missing or empty
    /// are recorded as failures (preserving existing behavior); discovery folders that are
    /// not plugins are simply skipped (verbose-logged). Explicit paths are collected first
    /// so they win folder-level de-duplication ties over discovery.
    /// </summary>
    private List<PluginCandidate> CollectCandidateFolders(PluginLoadResult result)
    {
        var candidates = new List<PluginCandidate>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var pluginPath in _options.Paths)
        {
            if (string.IsNullOrWhiteSpace(pluginPath))
                continue;

            // Skip missing or empty folders with a clear warning; never let this stop the
            // other plugins (or the host) from loading.
            if (!Directory.Exists(pluginPath))
            {
                _logger.LogWarning(
                    "Skipping plugin path '{Path}': folder does not exist.", pluginPath);
                result.Failed.Add(new FailedPlugin
                {
                    PluginPath = pluginPath,
                    Reason = "Plugin folder does not exist."
                });
                continue;
            }

            if (!Directory.EnumerateFileSystemEntries(pluginPath).Any())
            {
                _logger.LogWarning(
                    "Skipping plugin path '{Path}': folder is empty.", pluginPath);
                result.Failed.Add(new FailedPlugin
                {
                    PluginPath = pluginPath,
                    Reason = "Plugin folder is empty."
                });
                continue;
            }

            if (seen.Add(NormalizePath(pluginPath)))
            {
                LogVerbose("Explicit plugin folder queued: {Path}", pluginPath);
                candidates.Add(new PluginCandidate(pluginPath, PluginSource.Explicit));
            }
        }

        foreach (var root in _options.PluginRoots)
        {
            if (string.IsNullOrWhiteSpace(root))
                continue;

            if (!Directory.Exists(root))
            {
                _logger.LogWarning("Skipping plugin root '{Root}': folder does not exist.", root);
                continue;
            }

            LogVerbose("Scanning plugin root '{Root}' for plugins", root);

            foreach (var folder in DiscoverPluginFolders(root))
            {
                if (seen.Add(NormalizePath(folder)))
                {
                    LogVerbose("Discovered plugin folder: {Path}", folder);
                    candidates.Add(new PluginCandidate(folder, PluginSource.Discovered));
                }
                else
                {
                    LogVerbose("Skipping already-queued plugin folder: {Path}", folder);
                }
            }
        }

        return candidates;
    }

    /// <summary>
    /// Enumerates plugin folders under a discovery root using the assumed layout:
    /// <list type="bullet">
    /// <item><description>Flat: <c>&lt;root&gt;\&lt;name&gt;\manifest.json</c></description></item>
    /// <item><description>Versioned: <c>&lt;root&gt;\&lt;name&gt;\&lt;version&gt;\manifest.json</c></description></item>
    /// </list>
    /// A folder qualifies as a plugin only when it directly contains a
    /// <c>manifest.json</c>. Scanning is bounded to two levels below the root and never
    /// throws (I/O errors are logged and skipped).
    /// </summary>
    private IEnumerable<string> DiscoverPluginFolders(string root)
    {
        foreach (var nameDir in SafeEnumerateDirectories(root))
        {
            // Flat layout: the name folder itself is the plugin.
            if (HasManifest(nameDir))
            {
                yield return nameDir;
                continue;
            }

            // Versioned layout: look one level deeper for version folders with a manifest.
            var found = false;
            foreach (var versionDir in SafeEnumerateDirectories(nameDir))
            {
                if (HasManifest(versionDir))
                {
                    found = true;
                    yield return versionDir;
                }
            }

            if (!found)
            {
                LogVerbose("Skipping '{Folder}': no manifest.json found (not a plugin).", nameDir);
            }
        }
    }

    /// <summary>
    /// Phase 2. Reads the manifest for every candidate folder. A candidate whose manifest
    /// is missing or invalid is recorded as a failure and skipped, honoring
    /// <see cref="PluginOptions.ContinueOnError"/>.
    /// </summary>
    private List<ParsedCandidate> ReadCandidateManifests(
        IReadOnlyList<PluginCandidate> candidates,
        PluginLoadResult result)
    {
        var parsed = new List<ParsedCandidate>();

        foreach (var candidate in candidates)
        {
            try
            {
                LogVerbose("Reading manifest from {Path}", candidate.FolderPath);
                var manifest = PluginManifestReader.Read(candidate.FolderPath);
                parsed.Add(new ParsedCandidate(candidate, manifest));
            }
            catch (Exception ex)
            {
                RecordLoadFailure(result, candidate.FolderPath, manifest: null, ex);
                if (!_options.ContinueOnError)
                {
                    throw new InvalidOperationException(
                        $"Plugin loading failed for '{candidate.FolderPath}' and ContinueOnError is false.",
                        ex);
                }
            }
        }

        return parsed;
    }

    /// <summary>
    /// Phase 3. De-duplicates parsed candidates by plugin id. Policy: the HIGHEST
    /// <c>version</c> wins; an unparseable version sorts lowest; on an exact-version tie an
    /// explicit <see cref="PluginOptions.Paths"/> entry wins over a discovered one. Every
    /// dropped duplicate is logged so the choice is never a mystery.
    /// </summary>
    private List<ParsedCandidate> SelectHighestVersionPerId(IReadOnlyList<ParsedCandidate> parsed)
    {
        var winners = new List<ParsedCandidate>();

        foreach (var group in parsed.GroupBy(p => p.Manifest.Id, StringComparer.Ordinal))
        {
            var ordered = group
                .OrderByDescending(p => TryParseVersion(p.Manifest.Version, out var v) ? v : null)
                .ThenByDescending(p => p.Folder.Source == PluginSource.Explicit)
                .ToList();

            var winner = ordered[0];
            winners.Add(winner);

            for (var i = 1; i < ordered.Count; i++)
            {
                var dropped = ordered[i];
                _logger.LogWarning(
                    "Multiple versions of plugin '{Id}' found; using v{WinnerVersion} from '{WinnerPath}', ignoring v{DroppedVersion} from '{DroppedPath}'.",
                    winner.Manifest.Id,
                    winner.Manifest.Version,
                    winner.Folder.FolderPath,
                    dropped.Manifest.Version,
                    dropped.Folder.FolderPath);
            }

            if (ordered.Count > 1)
            {
                LogVerbose(
                    "Selected plugin '{Id}' v{Version} as the highest of {Count} candidate version(s).",
                    winner.Manifest.Id, winner.Manifest.Version, ordered.Count);
            }
        }

        return winners;
    }

    /// <summary>
    /// Phase 4. Loads a single selected plugin, reusing the existing per-plugin
    /// <see cref="PluginLoadContext"/> isolation model. Genuine load errors are isolated
    /// so one bad plugin never blocks the others.
    /// </summary>
    private void LoadCandidate(PluginLoadResult result, ParsedCandidate candidate)
    {
        var manifest = candidate.Manifest;
        var pluginPath = candidate.Folder.FolderPath;

        // Load and instantiate. Genuine errors here (bad DLL, reflection failures, etc.)
        // are real load failures, isolated so one bad plugin does not crash the host or
        // block the others.
        try
        {
            var loaded = LoadFromManifest(manifest);
            result.Loaded.Add(loaded);
            _logger.LogInformation(
                "Loaded plugin '{Id}' v{Version} from {Path} (source: {Source})",
                loaded.Manifest.Id,
                loaded.Manifest.Version,
                pluginPath,
                candidate.Folder.Source);
        }
        catch (Exception ex)
        {
            RecordLoadFailure(result, pluginPath, manifest, ex);
            if (!_options.ContinueOnError)
            {
                throw new InvalidOperationException(
                    $"Plugin loading failed for '{pluginPath}' and ContinueOnError is false.",
                    ex);
            }
        }
    }

    /// <summary>
    /// Emits the completion summary and the final list of successfully loaded plugins with
    /// their versions and source folders.
    /// </summary>
    private void LogFinalSummary(PluginLoadResult result)
    {
        _logger.LogInformation(
            "Plugin loading complete: {Loaded} loaded, {Failed} failed",
            result.Loaded.Count,
            result.Failed.Count);

        if (result.Loaded.Count > 0)
        {
            _logger.LogInformation(
                "Loaded plugins: {Extensions}",
                string.Join("; ", result.Loaded.Select(l =>
                    $"{l.Manifest.Id} v{l.Manifest.Version} <- {l.Manifest.PluginPath}")));
        }
        else
        {
            _logger.LogWarning("No extensions were loaded.");
        }
    }

    /// <summary>True when the folder directly contains a <c>manifest.json</c>.</summary>
    private static bool HasManifest(string folder) =>
        File.Exists(Path.Combine(folder, "manifest.json"));

    /// <summary>
    /// Enumerates immediate subdirectories of a folder, returning an empty sequence (with a
    /// warning) instead of throwing on access/IO errors, so a single unreadable folder never
    /// aborts discovery.
    /// </summary>
    private IEnumerable<string> SafeEnumerateDirectories(string folder)
    {
        try
        {
            return Directory.EnumerateDirectories(folder);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            _logger.LogWarning("Could not enumerate subfolders of '{Folder}': {Reason}", folder, ex.Message);
            return Array.Empty<string>();
        }
    }

    /// <summary>Normalizes a folder path for case-insensitive de-duplication.</summary>
    private static string NormalizePath(string path)
    {
        try
        {
            return Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        }
    }

    /// <summary>
    /// Builds a full, human-readable description of an exception including all
    /// inner exceptions and, for <see cref="ReflectionTypeLoadException"/>, every
    /// underlying loader exception (which is where the real cause usually hides).
    /// </summary>
    private static string DescribeException(Exception ex)
    {
        var sb = new System.Text.StringBuilder();

        for (var current = ex; current is not null; current = current.InnerException)
        {
            sb.Append(current.GetType().Name)
              .Append(": ")
              .Append(current.Message);

            if (current is ReflectionTypeLoadException rtle && rtle.LoaderExceptions.Length > 0)
            {
                sb.AppendLine();
                sb.Append("  LoaderExceptions:");
                foreach (var loaderEx in rtle.LoaderExceptions)
                {
                    if (loaderEx is null)
                        continue;
                    sb.AppendLine();
                    sb.Append("    - ")
                      .Append(loaderEx.GetType().Name)
                      .Append(": ")
                      .Append(loaderEx.Message);
                }
            }

            if (current.InnerException is not null)
            {
                sb.AppendLine();
                sb.Append(" ---> ");
            }
        }

        return sb.ToString();
    }

    /// <summary>
    /// Loads a single plugin from the specified folder.
    /// </summary>
    /// <param name="pluginFolderPath">The full path to the plugin folder.</param>
    /// <returns>The loaded plugin.</returns>
    public LoadedPlugin LoadPlugin(string pluginFolderPath)
    {
        if (!Directory.Exists(pluginFolderPath))
        {
            throw new DirectoryNotFoundException($"Plugin folder not found: '{pluginFolderPath}'");
        }

        // Step 1: Read and validate manifest
        LogVerbose("Reading manifest from {Path}", pluginFolderPath);
        var manifest = PluginManifestReader.Read(pluginFolderPath);

        return LoadFromManifest(manifest);
    }

    /// <summary>
    /// Loads and instantiates the extension described by an already-read manifest
    /// (create load context, preload, load entry assembly, instantiate the IExtension).
    /// </summary>
    /// <param name="manifest">The validated plugin manifest.</param>
    /// <returns>The loaded plugin.</returns>
    private LoadedPlugin LoadFromManifest(PluginManifest manifest)
    {
        // Step 1: Verify entry assembly exists
        if (!File.Exists(manifest.EntryAssemblyPath))
        {
            throw new FileNotFoundException(
                $"Entry assembly not found: '{manifest.EntryAssemblyPath}'",
                manifest.EntryAssemblyPath);
        }

        // Step 2: Create isolated load context
        LogVerbose("Creating AssemblyLoadContext for {Id}", manifest.Id);
        var loadContext = new PluginLoadContext(manifest.EntryAssemblyPath, manifest.Id);

        // Step 3: Preload any additional assemblies
        if (manifest.PreloadAssemblies is { Count: > 0 })
        {
            foreach (var preload in manifest.PreloadAssemblies)
            {
                var preloadPath = Path.Combine(manifest.PluginPath, preload);
                if (File.Exists(preloadPath))
                {
                    LogVerbose("Preloading {Assembly} for {Id}", preload, manifest.Id);
                    loadContext.LoadPlugin(preloadPath);
                }
                else
                {
                    _logger.LogWarning(
                        "Preload assembly '{Assembly}' not found for plugin '{Id}'",
                        preload,
                        manifest.Id);
                }
            }
        }

        // Step 4: Load the entry assembly
        LogVerbose("Loading entry assembly for {Id}", manifest.Id);
        var assembly = loadContext.LoadPlugin(manifest.EntryAssemblyPath);

        // Step 5: Find and instantiate the IExtension type
        LogVerbose("Instantiating {Type} for {Id}", manifest.EntryType, manifest.Id);
        var extensionType = assembly.GetType(manifest.EntryType);
        if (extensionType is null)
        {
            throw new TypeLoadException(
                $"Entry type '{manifest.EntryType}' not found in assembly '{manifest.EntryAssembly}'");
        }

        if (!typeof(IExtension).IsAssignableFrom(extensionType))
        {
            throw new InvalidOperationException(
                $"Type '{manifest.EntryType}' does not implement IExtension");
        }

        var extension = Activator.CreateInstance(extensionType) as IExtension;
        if (extension is null)
        {
            throw new InvalidOperationException(
                $"Failed to instantiate '{manifest.EntryType}' as IExtension");
        }

        return new LoadedPlugin
        {
            Manifest = manifest,
            LoadContext = loadContext,
            Assembly = assembly,
            Extension = extension
        };
    }

    /// <summary>
    /// Records a genuine plugin load failure (bad DLL, reflection error, missing or
    /// invalid manifest, etc.) into the result and logs full diagnostic detail.
    /// </summary>
    private void RecordLoadFailure(PluginLoadResult result, string pluginPath, PluginManifest? manifest, Exception ex)
    {
        result.Failed.Add(new FailedPlugin
        {
            PluginPath = pluginPath,
            Manifest = manifest,
            Reason = ex.Message,
            Exception = ex
        });

        _logger.LogError(
            ex,
            "Failed to load plugin from '{Path}': {Detail}",
            pluginPath,
            DescribeException(ex));
    }

    /// <summary>
    /// Gets the wwwroot paths for all plugins that have static assets.
    /// Used to configure static file serving for plugin web content.
    /// </summary>
    public IEnumerable<(string PluginId, string WwwrootPath)> GetStaticAssetPaths(PluginLoadResult result)
    {
        foreach (var loaded in result.Loaded)
        {
            if (loaded.Manifest.HasStaticAssets && Directory.Exists(loaded.Manifest.WwwrootPath))
            {
                yield return (loaded.Manifest.Id, loaded.Manifest.WwwrootPath);
            }
        }
    }

    /// <summary>-
    /// Safely parses a Semantic Version string using <see cref="Version"/>. Returns
    /// <c>false</c> for null, empty, or malformed values instead of throwing.
    /// </summary>
    private static bool TryParseVersion(string? raw, out Version? version)
    {
        version = null;
        if (string.IsNullOrWhiteSpace(raw))
        {
            return false;
        }

        return Version.TryParse(raw.Trim(), out version);
    }

    private void LogVerbose(string message, params object[] args)
    {
        if (_options.VerboseLogging)
        {
            _logger.LogDebug(message, args);
        }
    }
}
