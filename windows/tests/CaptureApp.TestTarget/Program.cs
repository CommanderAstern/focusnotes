namespace CaptureApp.TestTarget;

// Helper target app for Platform race tests; modes are added by the selection tests.
internal static class Program
{
    [STAThread]
    private static int Main(string[] args) => args.Length >= 0 ? 0 : 1;
}
