using System.Text.Json;

namespace NodeConfigurator.Abstractions;

/// <summary>
/// A message published on the <see cref="IEventBus"/>.
/// </summary>
/// <param name="Topic">The topic the message was published on (e.g. "ext.mode.changed").</param>
/// <param name="SourceId">Id of the component/extension that published the message.</param>
/// <param name="Payload">Opaque message payload as raw JSON.</param>
public record BusMessage(string Topic, string SourceId, JsonElement Payload);

/// <summary>
/// A lightweight in-process publish/subscribe message bus used for loose,
/// cross-extension communication (e.g. validation re-triggering and save signals).
/// </summary>
public interface IEventBus
{
    /// <summary>
    /// Subscribes <paramref name="handler"/> to the given <paramref name="topic"/>.
    /// </summary>
    /// <returns>A token that removes the subscription when disposed.</returns>
    IDisposable Subscribe(string topic, Action<BusMessage> handler);

    /// <summary>
    /// Publishes <paramref name="message"/> to all handlers subscribed to its topic.
    /// </summary>
    void Publish(BusMessage message);
}
