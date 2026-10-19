using System.Runtime.InteropServices;
using CaptureApp.AppCore;
using CaptureApp.Core;
using CaptureApp.Updates;

namespace CaptureApp.App;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        UpdateBootstrap.Run();

#if CI_UPDATE_TESTS
        if (args.Length > 0 && string.Equals(args[0], "--ci-update", StringComparison.Ordinal))
        {
            AttachConsoleIfNeeded();
            return CiUpdateCommand.RunAsync(args).GetAwaiter().GetResult();
        }
#endif

        if (args.Length > 0 && string.Equals(args[0], "--self-test", StringComparison.Ordinal))
        {
            AttachConsoleIfNeeded();
            try
            {
                if (args.Length != 2 && (args.Length != 4 || !string.Equals(args[2], "--models", StringComparison.Ordinal)))
                {
                    throw new ArgumentException("Usage: --self-test <dir> [--models <dir>]");
                }

                SelfTest.RunAsync(args[1], args.Length == 4 ? args[3] : null).GetAwaiter().GetResult();
                return 0;
            }
            catch (Exception error)
            {
                Console.Error.WriteLine($"Self-test failed: {error}");
                return 1;
            }
        }

        if (args.Contains("--version", StringComparer.Ordinal))
        {
            AttachConsoleIfNeeded();
            Console.WriteLine(AppInfo.Version);
        }

        return 0;
    }

    private static void AttachConsoleIfNeeded()
    {
        // A WinExe may start without stdout; keep inherited pipes when present.
        var output = GetStdHandle(-11);
        if (output == 0 || output == -1)
        {
            AttachConsole(uint.MaxValue);
        }
    }

    [DllImport("kernel32.dll")]
    private static extern nint GetStdHandle(int kind);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AttachConsole(uint processId);
}
