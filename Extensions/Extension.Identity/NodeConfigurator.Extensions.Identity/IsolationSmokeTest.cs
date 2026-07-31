using System.Reflection;
using System.Runtime.Loader;

namespace NodeConfigurator.Extensions.Identity;

/// <summary>
/// Repeatable dependency-isolation smoke test. It does two things:
/// <list type="number">
/// <item>"Touches" both isolated packages (Newtonsoft.Json + Markdig) so publish never
/// trims or drops their DLLs from the plugin folder.</item>
/// <item>Logs the loaded assembly version, on-disk location, and the AssemblyLoadContext
/// (ALC) name for each package — proving each plugin loads its own copy into its own ALC.</item>
/// </list>
/// This class performs NO UI work; it only writes to the console/log.
/// </summary>
internal static class IsolationSmokeTest
{
    /// <summary>
    /// Runs the smoke test for the given plugin id. The "touch" always runs (so the DLLs
    /// are genuinely used and kept in the output); logging is gated by <see cref="ShouldLog"/>.
    /// </summary>
    public static void Run(string pluginId)
    {
        // --- Touch both packages so they are real, used dependencies (no trimming). ---
        var newtonsoft = typeof(Newtonsoft.Json.JsonConvert).Assembly;
        _ = Newtonsoft.Json.JsonConvert.SerializeObject(new { ok = true });

        var markdigHtml = Markdig.Markdown.ToHtml("test");
        var markdig = typeof(Markdig.Markdown).Assembly;

        if (!ShouldLog())
            return;

        Log(pluginId, "Newtonsoft.Json", newtonsoft);
        Log(pluginId, "Markdig", markdig);
        Console.WriteLine(
            $"[isolation][{pluginId}] Markdig.ToHtml(\"test\") produced {markdigHtml.Trim().Length} chars.");
    }

    /// <summary>
    /// Logging is enabled in DEBUG builds, or in any build when the
    /// NODECONFIG_ISOLATION_LOG environment variable is set to "1" (config flag),
    /// so it also works with the Release publish used for deployment.
    /// </summary>
    private static bool ShouldLog()
    {
#if DEBUG
        return true;
#else
        return string.Equals(
            Environment.GetEnvironmentVariable("NODECONFIG_ISOLATION_LOG"),
            "1",
            StringComparison.Ordinal);
#endif
    }

    private static void Log(string pluginId, string name, Assembly asm)
    {
        var alcName = AssemblyLoadContext.GetLoadContext(asm)?.Name ?? "(default)";
        Console.WriteLine(
            $"[isolation][{pluginId}] {name} v{asm.GetName().Version} | ALC={alcName} | {asm.Location}");
    }
}
