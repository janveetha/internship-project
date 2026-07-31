namespace NodeConfigurator.Core.Plugins;

/// <summary>
/// Configuration options for the plugin loading system.
/// Bound from the "Plugins" section of appsettings.json.
/// </summary>
public sealed class PluginOptions
{
    /// <summary>
    /// The configuration section name in appsettings.json.
    /// </summary>
    public const string SectionName = "Plugins";

    /// <summary>
    /// List of folder paths where plugins are located.
    /// Each path should point to a folder containing a manifest.json file.
    /// </summary>
    /// <example>
    /// <code>
    /// "Plugins": {
    ///   "Paths": [
    ///     "C:/plugins/identity/1.0.0",
    ///     "C:/plugins/mode/1.0.0"
    ///   ]
    /// }
    /// </code>
    /// </example>
    public List<string> Paths { get; set; } = new();

    /// <summary>
    /// Root folder(s) the host SCANS for plugins at startup. Every immediate subfolder
    /// is inspected: a folder that directly contains a <c>manifest.json</c> is treated as
    /// a plugin (flat layout <c>&lt;root&gt;\&lt;name&gt;</c>); otherwise the host looks one level
    /// deeper for versioned layouts (<c>&lt;root&gt;\&lt;name&gt;\&lt;version&gt;</c>). Drop a new
    /// plugin folder under a configured root and it loads on next start with no config edit.
    /// </summary>
    /// <remarks>
    /// Discovered plugins are merged with <see cref="Paths"/>. When the same plugin id is
    /// found more than once (e.g. two versioned folders), the HIGHEST <c>version</c> wins;
    /// on an exact-version tie an explicit <see cref="Paths"/> entry wins over a discovered
    /// one. Empty by default, preserving the original explicit-paths-only behavior.
    /// </remarks>
    /// <example>
    /// <code>
    /// "Plugins": {
    ///   "PluginRoots": [ "C:/plugins" ]
    /// }
    /// </code>
    /// </example>
    public List<string> PluginRoots { get; set; } = new();

    /// <summary>
    /// Whether to continue loading other plugins if one fails to load.
    /// Default is true (fault-tolerant).
    /// </summary>
    public bool ContinueOnError { get; set; } = true;

    /// <summary>
    /// Whether to enable verbose logging during plugin discovery and loading.
    /// </summary>
    public bool VerboseLogging { get; set; } = false;
}
