using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Core.Plugins;

/// <summary>
/// A mutable registry for runtime-loaded plugin extensions. Unlike the compile-time
/// <see cref="ExtensionRegistry"/> that receives extensions via DI, this registry
/// allows extensions to be added after the DI container is built.
/// </summary>
/// <remarks>
/// This registry provides both the IExtension instances (for the extension system)
/// and the concrete types (for Blazor component injection). Since plugins are loaded
/// dynamically, we can't register concrete types in DI ahead of time.
/// </remarks>
public sealed class PluginExtensionRegistry
{
    private readonly List<LoadedPlugin> _plugins = new();
    private readonly object _lock = new();

    /// <summary>All loaded plugin extensions, in load order.</summary>
    public IReadOnlyList<IExtension> Extensions
    {
        get
        {
            lock (_lock)
            {
                return _plugins.Select(p => p.Extension).ToList();
            }
        }
    }

    /// <summary>All loaded plugins with full metadata.</summary>
    public IReadOnlyList<LoadedPlugin> Plugins
    {
        get
        {
            lock (_lock)
            {
                return _plugins.ToList();
            }
        }
    }

    /// <summary>
    /// Registers a loaded plugin into the registry.
    /// </summary>
    public void Register(LoadedPlugin plugin)
    {
        lock (_lock)
        {
            // Prevent duplicate registration
            if (_plugins.Any(p => p.Manifest.Id == plugin.Manifest.Id))
            {
                throw new InvalidOperationException(
                    $"Plugin '{plugin.Manifest.Id}' is already registered");
            }

            _plugins.Add(plugin);
        }
    }

    /// <summary>
    /// Registers multiple loaded plugins into the registry.
    /// </summary>
    public void RegisterAll(IEnumerable<LoadedPlugin> plugins)
    {
        foreach (var plugin in plugins)
        {
            Register(plugin);
        }
    }

    /// <summary>Gets an extension by id, or null if not found.</summary>
    public IExtension? GetExtension(string id)
    {
        lock (_lock)
        {
            return _plugins
                .Select(p => p.Extension)
                .FirstOrDefault(e => string.Equals(e.Id, id, StringComparison.Ordinal));
        }
    }

    /// <summary>Gets a loaded plugin by id, or null if not found.</summary>
    public LoadedPlugin? GetPlugin(string id)
    {
        lock (_lock)
        {
            return _plugins.FirstOrDefault(p => p.Manifest.Id == id);
        }
    }

    /// <summary>
    /// Gets the concrete extension instance cast to a specific type.
    /// Used by Blazor components that need to inject the concrete extension type.
    /// </summary>
    /// <typeparam name="T">The concrete extension type.</typeparam>
    /// <returns>The extension instance, or null if not found or wrong type.</returns>
    public T? GetExtension<T>() where T : class, IExtension
    {
        lock (_lock)
        {
            return _plugins
                .Select(p => p.Extension)
                .OfType<T>()
                .FirstOrDefault();
        }
    }
}
