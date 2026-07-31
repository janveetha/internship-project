using System.Text.Json;
using System.Text.Json.Serialization;

namespace NodeConfigurator.Core.Plugins;

/// <summary>
/// Represents the manifest.json file that describes a plugin. Each plugin folder
/// must contain this file at its root.
/// </summary>
public sealed class PluginManifest
{
    /// <summary>Stable unique identifier for the plugin (e.g., "ext.identity").</summary>
    [JsonPropertyName("id")]
    public required string Id { get; init; }

    /// <summary>Human-readable name shown in UI.</summary>
    [JsonPropertyName("displayName")]
    public required string DisplayName { get; init; }

    /// <summary>Plugin version (semver, e.g., "1.0.0").</summary>
    [JsonPropertyName("version")]
    public required string Version { get; init; }

    /// <summary>
    /// The entry assembly filename (e.g., "NodeConfigurator.Extensions.Identity.dll").
    /// Relative to the plugin folder.
    /// </summary>
    [JsonPropertyName("entryAssembly")]
    public required string EntryAssembly { get; init; }

    /// <summary>
    /// The fully-qualified type name of the IExtension implementation
    /// (e.g., "NodeConfigurator.Extensions.Identity.IdentityExtension").
    /// </summary>
    [JsonPropertyName("entryType")]
    public required string EntryType { get; init; }

    /// <summary>
    /// Whether the plugin includes static web assets (wwwroot folder).
    /// When true, the host will serve assets from the plugin's wwwroot directory.
    /// </summary>
    [JsonPropertyName("hasStaticAssets")]
    public bool HasStaticAssets { get; init; }

    /// <summary>
    /// Optional list of additional assemblies to preload before instantiating the entry type.
    /// Useful when the plugin has dependencies that must be loaded explicitly.
    /// </summary>
    [JsonPropertyName("preloadAssemblies")]
    public List<string>? PreloadAssemblies { get; init; }

    /// <summary>
    /// The full path to the plugin folder (set after loading, not serialized).
    /// </summary>
    [JsonIgnore]
    public string PluginPath { get; set; } = string.Empty;

    /// <summary>
    /// The full path to the entry assembly (computed from PluginPath + EntryAssembly).
    /// </summary>
    [JsonIgnore]
    public string EntryAssemblyPath => Path.Combine(PluginPath, EntryAssembly);

    /// <summary>
    /// The full path to the wwwroot folder (if HasStaticAssets is true).
    /// </summary>
    [JsonIgnore]
    public string WwwrootPath => Path.Combine(PluginPath, "wwwroot");
}

/// <summary>
/// Reads and validates plugin manifests from disk.
/// </summary>
public static class PluginManifestReader
{
    private const string ManifestFileName = "manifest.json";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true
    };

    /// <summary>
    /// Reads and parses the manifest.json from the specified plugin folder.
    /// </summary>
    /// <param name="pluginFolderPath">The full path to the plugin folder.</param>
    /// <returns>The parsed manifest with PluginPath set.</returns>
    /// <exception cref="FileNotFoundException">If manifest.json doesn't exist.</exception>
    /// <exception cref="InvalidOperationException">If the manifest is invalid.</exception>
    public static async Task<PluginManifest> ReadAsync(string pluginFolderPath)
    {
        var manifestPath = Path.Combine(pluginFolderPath, ManifestFileName);

        if (!File.Exists(manifestPath))
        {
            throw new FileNotFoundException(
                $"Plugin manifest not found at '{manifestPath}'.",
                manifestPath);
        }

        await using var stream = File.OpenRead(manifestPath);
        var manifest = await JsonSerializer.DeserializeAsync<PluginManifest>(stream, JsonOptions);

        if (manifest is null)
        {
            throw new InvalidOperationException(
                $"Failed to deserialize plugin manifest at '{manifestPath}'.");
        }

        // Validate required fields
        ValidateManifest(manifest, manifestPath);

        // Set the plugin path for later use
        manifest.PluginPath = pluginFolderPath;

        return manifest;
    }

    /// <summary>
    /// Synchronous version of ReadAsync for scenarios where async isn't available.
    /// </summary>
    public static PluginManifest Read(string pluginFolderPath)
    {
        var manifestPath = Path.Combine(pluginFolderPath, ManifestFileName);

        if (!File.Exists(manifestPath))
        {
            throw new FileNotFoundException(
                $"Plugin manifest not found at '{manifestPath}'.",
                manifestPath);
        }

        var json = File.ReadAllText(manifestPath);
        var manifest = JsonSerializer.Deserialize<PluginManifest>(json, JsonOptions);

        if (manifest is null)
        {
            throw new InvalidOperationException(
                $"Failed to deserialize plugin manifest at '{manifestPath}'.");
        }

        ValidateManifest(manifest, manifestPath);
        manifest.PluginPath = pluginFolderPath;

        return manifest;
    }

    private static void ValidateManifest(PluginManifest manifest, string manifestPath)
    {
        var errors = new List<string>();

        if (string.IsNullOrWhiteSpace(manifest.Id))
            errors.Add("'id' is required");

        if (string.IsNullOrWhiteSpace(manifest.DisplayName))
            errors.Add("'displayName' is required");

        if (string.IsNullOrWhiteSpace(manifest.Version))
            errors.Add("'version' is required");

        if (string.IsNullOrWhiteSpace(manifest.EntryAssembly))
            errors.Add("'entryAssembly' is required");

        if (string.IsNullOrWhiteSpace(manifest.EntryType))
            errors.Add("'entryType' is required");

        if (errors.Count > 0)
        {
            throw new InvalidOperationException(
                $"Invalid plugin manifest at '{manifestPath}': {string.Join(", ", errors)}");
        }
    }
}
