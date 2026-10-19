using Velopack;

namespace CaptureApp.Updates;

/// <summary>Velopack startup hook; must be the first thing <c>Main</c> does.</summary>
public static class UpdateBootstrap
{
    /// <summary>True when this launch is the first run after a fresh install (the Setup flow reads it).</summary>
    public static bool IsFirstRun { get; private set; }

    public static void Run() =>
        VelopackApp.Build().OnFirstRun(_ => IsFirstRun = true).Run();
}
