using System.Reflection;
using System.Runtime.Loader;

namespace NodeConfigurator.Core.Plugins;

/// <summary>
/// A custom <see cref="AssemblyLoadContext"/> that maximally isolates each plugin's
/// dependencies, sharing with the host ONLY the small set of assemblies whose types
/// actually cross the host&lt;-&gt;plugin boundary.
/// </summary>
/// <remarks>
/// <para>
/// Two categories of assemblies can NEVER be isolated per plugin while running
/// in-process, because doing so would break type identity:
/// </para>
/// <para>
/// 1. <b>The base runtime</b> (System.Private.CoreLib, System.Runtime, netstandard,
/// etc.). These are unified automatically by the CLR — every load context resolves
/// them to the single runtime copy. We do not (and must not) try to load our own
/// copies of them. This is handled by the runtime, not by this class.
/// </para>
/// <para>
/// 2. <b>The boundary contract</b> — the assemblies whose <i>types appear on the
/// public surface exchanged between the host and plugins</i> (see
/// <see cref="BoundaryAssemblyNames"/>). If a plugin loaded its own copy of these,
/// its <c>IExtension</c>, <c>JsonElement</c>, or <c>ComponentBase</c> would be a
/// <i>different</i> <see cref="Type"/> than the host's, and casts / rendering would
/// fail with confusing <c>InvalidCastException</c>s. These must resolve to the
/// host's already-loaded copy.
/// </para>
/// <para>
/// <b>Everything else is now isolated per plugin.</b> Internal dependencies whose
/// types never cross the boundary (e.g. Newtonsoft.Json, Microsoft.Extensions.Http,
/// and even System.Text.Json when it is <i>not</i> on the contract surface) are
/// loaded from the plugin's own folder. This lets two plugins ship different
/// versions of the same library and coexist without version clashes.
/// </para>
/// </remarks>
public sealed class PluginLoadContext : AssemblyLoadContext
{
    private readonly AssemblyDependencyResolver _resolver;
    private readonly string _pluginPath;

    /// <summary>
    /// The MINIMAL set of exact-match assemblies force-shared with the host's default
    /// context. An assembly belongs here only if its TYPES appear on the public surface
    /// that is passed between the host and plugins — sharing guarantees a single
    /// <see cref="Type"/> identity for those types on both sides.
    /// </summary>
    /// <remarks>
    /// Derived by inspecting the NodeConfigurator.Abstractions contract surface
    /// (<c>IExtension</c>, <c>IExtensionContext</c>, <c>BusMessage</c>, models) and how
    /// the host consumes it:
    /// <list type="bullet">
    /// <item><b>NodeConfigurator.Abstractions</b> — the contract itself
    /// (<c>IExtension</c>, <c>IExtensionContext</c>, <c>Node</c>, <c>BusMessage</c>, …).
    /// The plugin implements it and the host consumes it, so both must see one type.</item>
    /// <item><b>System.Text.Json</b> — <c>System.Text.Json.JsonElement</c> is on the
    /// contract surface: <c>IExtension.SerializeConfig()</c> returns it,
    /// <c>HydrateAsync(JsonElement?)</c> accepts it, and <c>BusMessage.Payload</c> is one.
    /// A <c>JsonElement</c> is passed by value across the boundary, so its type MUST be
    /// unified. NOTE: System.Text.Json cannot currently be isolated for this reason;
    /// isolating it would require changing the contract to pass JSON as a <c>string</c>
    /// (and each side would parse with its own System.Text.Json copy).</item>
    /// <item><b>Microsoft.JSInterop</b> — Blazor JS interop (<c>IJSRuntime</c>) flows
    /// through the shared Blazor rendering/injection pipeline into plugin components, so
    /// its types must be unified with the host.</item>
    /// <item><b>Microsoft.Extensions.DependencyInjection.Abstractions</b> — plugin
    /// components are injected by the host's DI/Blazor pipeline (<c>[Inject]</c>,
    /// <c>IServiceProvider</c>); the abstractions type identity must match the host.</item>
    /// <item><b>Microsoft.Extensions.Logging.Abstractions</b> — <c>ILogger</c>/
    /// <c>ILogger&lt;T&gt;</c> injected into plugin components via the same shared Blazor
    /// injection pipeline; identity must match the host.</item>
    /// </list>
    /// The Blazor component model assemblies (<c>Microsoft.AspNetCore.Components*</c>) are
    /// matched by prefix in <see cref="BoundaryAssemblyPrefixes"/> because a plugin's Razor
    /// component derives from <c>ComponentBase</c>/<c>IComponent</c> and the host renders it
    /// via <c>DynamicComponent Type="extension.ComponentType"</c>; the host's renderer must
    /// recognize the plugin type as its own <c>IComponent</c>.
    /// <para>
    /// Deliberately NOT shared (no types on the contract surface, so they are isolated
    /// per plugin): Newtonsoft.Json, Microsoft.Extensions.Http, System.Memory, and other
    /// third-party / internal dependencies. Plugins can independently version these.
    /// </para>
    /// </remarks>
    private static readonly HashSet<string> BoundaryAssemblyNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "NodeConfigurator.Abstractions",
        "System.Text.Json",
        "Microsoft.JSInterop",
        "Microsoft.Extensions.DependencyInjection.Abstractions",
        "Microsoft.Extensions.Logging.Abstractions"
    };

    /// <summary>
    /// Prefix-matched boundary assemblies. All of the Blazor component-model assemblies
    /// (<c>Microsoft.AspNetCore.Components</c>, <c>...Components.Web</c>, etc.) must be
    /// unified with the host so plugin Razor components render inside the host renderer.
    /// </summary>
    private static readonly string[] BoundaryAssemblyPrefixes =
    {
        "Microsoft.AspNetCore.Components"
    };

    /// <summary>
    /// Creates a new plugin load context for the specified plugin assembly.
    /// </summary>
    /// <param name="pluginAssemblyPath">
    /// The full path to the plugin's entry assembly (e.g., "C:/plugins/identity/1.0.0/Plugin.dll").
    /// The .deps.json file should be alongside this assembly.
    /// </param>
    /// <param name="pluginId">
    /// A friendly name for this context (used in diagnostics and for collectability).
    /// </param>
    public PluginLoadContext(string pluginAssemblyPath, string pluginId)
        : base(name: $"Plugin:{pluginId}", isCollectible: true)
    {
        _pluginPath = Path.GetDirectoryName(pluginAssemblyPath)
            ?? throw new ArgumentException("Invalid plugin path", nameof(pluginAssemblyPath));

        // AssemblyDependencyResolver reads the .deps.json file to resolve dependencies
        // from the plugin's folder structure (including runtime-specific folders)
        _resolver = new AssemblyDependencyResolver(pluginAssemblyPath);
    }

    /// <summary>
    /// Resolves and loads an assembly by name.
    /// </summary>
    /// <remarks>
    /// Resolution order — "isolate what the plugin ships":
    /// <list type="number">
    /// <item>If it is a boundary assembly, return <c>null</c> so the runtime resolves it
    /// from the host's default context (preserves type identity across the boundary).</item>
    /// <item>Else if the plugin shipped it (the .deps.json resolver finds it in the plugin
    /// folder), load an ISOLATED copy from that path — this is how two plugins can use
    /// different versions of the same internal dependency.</item>
    /// <item>Else return <c>null</c>: it is a framework/runtime assembly provided by the
    /// host / base runtime, so let the default context supply it.</item>
    /// </list>
    /// </remarks>
    protected override Assembly? Load(AssemblyName assemblyName)
    {
        // (a) Boundary assemblies MUST come from the default context so that types
        // exchanged with the host (IExtension, JsonElement, ComponentBase, ...) have a
        // single Type identity. Returning null defers to the default context.
        if (IsBoundaryAssembly(assemblyName))
        {
            return null;
        }

        // (b) Anything the plugin actually shipped (declared in its .deps.json) is loaded
        // as an ISOLATED copy from the plugin folder, so plugins never clash on versions
        // of their internal dependencies.
        var assemblyPath = _resolver.ResolveAssemblyToPath(assemblyName);
        if (assemblyPath is not null)
        {
            return LoadFromAssemblyPath(assemblyPath);
        }

        // (c) Not on the boundary and not shipped by the plugin => a framework/runtime
        // assembly provided by the host. Defer to the default context.
        return null;
    }

    /// <summary>
    /// Resolves native libraries for the plugin.
    /// </summary>
    protected override IntPtr LoadUnmanagedDll(string unmanagedDllName)
    {
        var libraryPath = _resolver.ResolveUnmanagedDllToPath(unmanagedDllName);
        if (libraryPath is not null)
        {
            return LoadUnmanagedDllFromPath(libraryPath);
        }

        return IntPtr.Zero;
    }

    /// <summary>
    /// Determines whether an assembly is a boundary assembly — one whose types cross the
    /// host&lt;-&gt;plugin surface and therefore MUST be loaded from the host's default
    /// context to keep a single <see cref="Type"/> identity. See
    /// <see cref="BoundaryAssemblyNames"/> for the exact set and the rationale per entry.
    /// </summary>
    private static bool IsBoundaryAssembly(AssemblyName assemblyName)
    {
        var name = assemblyName.Name;
        if (name is null)
        {
            return false;
        }

        if (BoundaryAssemblyNames.Contains(name))
        {
            return true;
        }

        foreach (var prefix in BoundaryAssemblyPrefixes)
        {
            if (name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// Loads the plugin's entry assembly and returns it.
    /// </summary>
    /// <param name="assemblyPath">The full path to the entry assembly.</param>
    public Assembly LoadPlugin(string assemblyPath)
    {
        return LoadFromAssemblyPath(assemblyPath);
    }
}
