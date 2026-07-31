using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Core;

/// <summary>
/// Read-only catalog mapping extension ids to their <see cref="IExtension"/>
/// instances (which also carry <c>ComponentType</c> and <c>DisplayName</c>).
/// </summary>
public sealed class ExtensionRegistry
{
    /// <summary>All registered extensions, in registration order.</summary>
    public IReadOnlyList<IExtension> Extensions { get; }

    public ExtensionRegistry(IEnumerable<IExtension> extensions)
    {
        Extensions = extensions.ToList();
    }

    /// <summary>Gets an extension by id, or null if not found.</summary>
    public IExtension? Get(string id) =>
        Extensions.FirstOrDefault(e => string.Equals(e.Id, id, StringComparison.Ordinal));
}
