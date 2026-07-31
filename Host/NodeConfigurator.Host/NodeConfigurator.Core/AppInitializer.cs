using System.Text.Json;
using Microsoft.Extensions.Logging;
using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Core;

/// <summary>
/// Orchestrates application startup: loads the snapshot, restores nodes, initializes
/// and hydrates each extension, then applies the persisted shell state. When no
/// saved state exists it seeds a small random set of nodes.
/// </summary>
public sealed class AppInitializer
{
    private readonly IStateStore _store;
    private readonly NodeStore _nodes;
    private readonly INavigationService _navigation;
    private readonly IExtensionContext _context;
    private readonly IReadOnlyList<IExtension> _extensions;
    private readonly ILogger<AppInitializer>? _logger;
    private bool _initialized;

    public AppInitializer(
        IStateStore store,
        NodeStore nodes,
        INavigationService navigation,
        IExtensionContext context,
        IEnumerable<IExtension> extensions,
        ILogger<AppInitializer>? logger = null)
    {
        _store = store;
        _nodes = nodes;
        _navigation = navigation;
        _context = context;
        _extensions = extensions.ToList();
        _logger = logger;
    }

    /// <summary>Runs the load/restore sequence once. Subsequent calls are no-ops.</summary>
    public async Task InitializeAsync()
    {
        if (_initialized)
            return;
        _initialized = true;

        var snapshot = await _store.LoadAsync().ConfigureAwait(false);

        // Populate the node list FIRST so the UI always has nodes to show, even if
        // one or more extensions fail to initialize/hydrate below.
        _nodes.Nodes = snapshot?.Nodes ?? GenerateRandomNodes();

        // Initialize and hydrate each extension in isolation. A single failing
        // extension must never abort startup or blank the node list.
        foreach (var ext in _extensions)
        {
            try
            {
                await ext.InitializeAsync(_context).ConfigureAwait(false);

                JsonElement? slice = null;
                if (snapshot is not null &&
                    snapshot.Extensions.TryGetValue(ext.Id, out var saved))
                {
                    slice = saved.Config;
                }

                await ext.HydrateAsync(slice).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                // Log and skip; keep loading the remaining extensions and continue
                // startup so the node list and navigation still initialize.
                _logger?.LogError(
                    ex,
                    "Extension '{ExtensionId}' ({Type}) failed during initialization/hydration and was skipped: {Message}",
                    ext.Id,
                    ext.GetType().Name,
                    ex.Message);
            }
        }

        // Navigation setup ALWAYS runs, regardless of extension failures above.
        string? nodeId;
        string? extensionId;

        if (snapshot is null)
        {
            nodeId = _nodes.Nodes.FirstOrDefault()?.Id;
            extensionId = _extensions.FirstOrDefault()?.Id;
        }
        else
        {
            nodeId = snapshot.Shell.SelectedNodeId;
            if (nodeId is null || _nodes.Nodes.All(n => n.Id != nodeId))
                nodeId = _nodes.Nodes.FirstOrDefault()?.Id;

            extensionId = snapshot.Shell.ActiveExtensionId;
            if (extensionId is null || _extensions.All(e => e.Id != extensionId))
                extensionId = _extensions.FirstOrDefault()?.Id;
        }

        _navigation.ActivateExtension(extensionId);
        _navigation.SelectNode(nodeId);
        _navigation.SetActivePane(snapshot?.Shell.ActivePane ?? ActivePane.Node);
    }

    private static List<Node> GenerateRandomNodes()
    {
        var random = new Random();
        var count = random.Next(3, 6); // 3..5 inclusive
        var nodes = new List<Node>(count);
        for (var i = 1; i <= count; i++)
            nodes.Add(new Node(Guid.NewGuid().ToString("N"), $"Computer-{i}"));

        return nodes;
    }
}
