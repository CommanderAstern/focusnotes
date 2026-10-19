using System.Runtime.InteropServices;
using CaptureApp.Core;

namespace CaptureApp.App;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Contains("--version", StringComparer.Ordinal))
        {
            // A WinExe may start without stdout; keep inherited pipes when present.
            var output = GetStdHandle(-11);
            if (output == 0 || output == -1)
            {
                AttachConsole(uint.MaxValue);
            }

            Console.WriteLine(AppInfo.Version);
        }
    }
    [DllImport("kernel32.dll")]
    private static extern nint GetStdHandle(int kind);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AttachConsole(uint processId);
}
