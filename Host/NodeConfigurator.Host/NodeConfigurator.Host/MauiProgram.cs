using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.Maui.Storage;
using NodeConfigurator.Abstractions;
using NodeConfigurator.Core;
using NodeConfigurator.Core.Plugins;

namespace NodeConfigurator.Host
{
    public static class MauiProgram
    {
        public static MauiApp CreateMauiApp()
        {
            var builder = MauiApp.CreateBuilder();
            builder
                .UseMauiApp<App>()
                .ConfigureFonts(fonts =>
                {
                    fonts.AddFont("OpenSans-Regular.ttf", "OpenSansRegular");
                });

            // Load configuration from appsettings.json
            var configPath = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
            if (File.Exists(configPath))
            {
                builder.Configuration.AddJsonFile(configPath, optional: true, reloadOnChange: false);
            }

            builder.Services.AddMauiBlazorWebView();

#if DEBUG
            builder.Services.AddBlazorWebViewDeveloperTools();
            builder.Logging.AddDebug();
#endif

            // Configure plugin options from appsettings.json
            builder.Services.Configure<PluginOptions>(
                builder.Configuration.GetSection(PluginOptions.SectionName));

            // Load plugins BEFORE building the container so we can register each
            // concrete extension type into DI. Plugin Blazor views inject their
            // concrete extension type (e.g. [Inject] ModeExtension), which Blazor
            // resolves from the host container when a DynamicComponent renders them.
            // If we registered them after Build(), those injections would throw
            // "No service for type ... has been registered" at render time.
            var pluginRegistry = new PluginExtensionRegistry();
            LoadPlugins(builder.Services, builder.Configuration, pluginRegistry);

            // Register the populated registry instance so every consumer (the
            // IEnumerable<IExtension> bridge, etc.) sees the loaded plugins.
            builder.Services.AddSingleton(pluginRegistry);
            builder.Services.AddSingleton<PluginLoader>();

            // Bridge: IEnumerable<IExtension> now comes from the plugin registry
            builder.Services.AddSingleton<IEnumerable<IExtension>>(sp =>
                sp.GetRequiredService<PluginExtensionRegistry>().Extensions);

            RegisterAppServices(builder.Services);

            // Build the app
            var app = builder.Build();

            return app;
        }

        private static void RegisterAppServices(IServiceCollection services)
        {
            // Core infrastructure services.
            services.AddSingleton<IEventBus, InMemoryEventBus>();
            services.AddSingleton<ISharedStateStore, SharedStateStore>();
            services.AddSingleton<INavigationService, NavigationService>();
            services.AddSingleton<NodeStore>();

            // State is persisted as a single JSON file in the app data directory.
            var statePath = Path.Combine(FileSystem.AppDataDirectory, "nodeconfigurator.json");
            services.AddSingleton<IStateStore>(_ => new JsonStateStore(statePath));

            services.AddSingleton<ISaveCoordinator, SaveCoordinator>();
            services.AddSingleton<IExtensionContext, ExtensionContext>();
            services.AddSingleton<ExtensionRegistry>();
            services.AddSingleton<AppInitializer>();

            // Note: Extensions are loaded at runtime from plugin folders.
            // They are registered into PluginExtensionRegistry in LoadPlugins().
            // The IEnumerable<IExtension> bridge above provides them to existing services.
        }

        private static void LoadPlugins(
            IServiceCollection services,
            IConfiguration configuration,
            PluginExtensionRegistry pluginRegistry)
        {
            // Build a temporary logger/options to drive the loader before the app
            // container exists.
            using var loggerFactory = LoggerFactory.Create(logging =>
            {
#if DEBUG
                logging.AddDebug();
#endif
            });
            var logger = loggerFactory.CreateLogger("PluginStartup");

            var options = new PluginOptions();
            configuration.GetSection(PluginOptions.SectionName).Bind(options);
            var pluginLoader = new PluginLoader(Options.Create(options), loggerFactory.CreateLogger<PluginLoader>());

            try
            {
                logger.LogInformation("Loading plugins...");
                var result = pluginLoader.LoadAll();

                // Register loaded plugins into the pre-build registry.
                pluginRegistry.RegisterAll(result.Loaded);

                // CRITICAL: register each concrete extension instance under its own
                // runtime type so plugin Blazor views can [Inject] them.
                foreach (var loaded in result.Loaded)
                {
                    services.AddSingleton(loaded.Extension.GetType(), loaded.Extension);

                    logger.LogInformation(
                        "✓ Plugin '{Id}' v{Version} loaded from {Path} (registered type {Type})",
                        loaded.Manifest.Id,
                        loaded.Manifest.Version,
                        loaded.Manifest.PluginPath,
                        loaded.Extension.GetType().FullName);
                }

                foreach (var failed in result.Failed)
                {
                    logger.LogWarning(
                        "✗ Plugin at '{Path}' failed: {Reason}",
                        failed.PluginPath,
                        failed.Reason);
                }

                logger.LogInformation(
                    "Plugin loading complete: {Loaded} loaded, {Failed} failed",
                    result.Loaded.Count,
                    result.Failed.Count);

                if (result.Loaded.Count == 0)
                {
                    logger.LogWarning(
                        "No plugins loaded. To add plugins, configure 'Plugins:Paths' in appsettings.json");
                }
            }
            catch (Exception ex)
            {
                // Never let plugin loading crash host startup; log and continue so
                // the shell still renders (with whatever loaded successfully).
                logger.LogError(ex, "Critical error during plugin loading");
            }
        }
    }
}
