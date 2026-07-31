using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Core;

/// <summary>
/// A simple thread-safe, in-process implementation of <see cref="IEventBus"/>.
/// </summary>
public sealed class InMemoryEventBus : IEventBus
{
    private readonly object _gate = new();
    private readonly Dictionary<string, List<Action<BusMessage>>> _handlers = new();

    /// <inheritdoc />
    public IDisposable Subscribe(string topic, Action<BusMessage> handler)
    {
        lock (_gate)
        {
            if (!_handlers.TryGetValue(topic, out var list))
            {
                list = new List<Action<BusMessage>>();
                _handlers[topic] = list;
            }

            list.Add(handler);
        }

        return new Subscription(this, topic, handler);
    }

    /// <inheritdoc />
    public void Publish(BusMessage message)
    {
        Action<BusMessage>[] snapshot;
        lock (_gate)
        {
            if (!_handlers.TryGetValue(message.Topic, out var list) || list.Count == 0)
                return;

            snapshot = list.ToArray();
        }

        foreach (var handler in snapshot)
            handler(message);
    }

    private void Unsubscribe(string topic, Action<BusMessage> handler)
    {
        lock (_gate)
        {
            if (!_handlers.TryGetValue(topic, out var list))
                return;

            list.Remove(handler);
            if (list.Count == 0)
                _handlers.Remove(topic);
        }
    }

    private sealed class Subscription : IDisposable
    {
        private InMemoryEventBus? _bus;
        private readonly string _topic;
        private readonly Action<BusMessage> _handler;

        public Subscription(InMemoryEventBus bus, string topic, Action<BusMessage> handler)
        {
            _bus = bus;
            _topic = topic;
            _handler = handler;
        }

        public void Dispose()
        {
            _bus?.Unsubscribe(_topic, _handler);
            _bus = null;
        }
    }
}
