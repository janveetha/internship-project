using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Host
{
    public partial class App : Application
    {
        private readonly IServiceProvider _services;

        public App(IServiceProvider services)
        {
            InitializeComponent();
            _services = services;
        }

        protected override Window CreateWindow(IActivationState? activationState)
        {
            var window = new Window(new MainPage()) { Title = "NodeConfigurator.Host" };

            // Persist the current state when the application window is closing.
            window.Destroying += async (_, _) =>
            {
                var saveCoordinator = _services.GetService(typeof(ISaveCoordinator)) as ISaveCoordinator;
                if (saveCoordinator is not null)
                    await saveCoordinator.SaveNow();
            };

            return window;
        }
    }
}
