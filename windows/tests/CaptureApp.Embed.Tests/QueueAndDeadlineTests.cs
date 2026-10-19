using Xunit;

namespace CaptureApp.Embed.Tests;

public sealed class QueueAndDeadlineTests
{
    [Fact]
    public async Task DeadlineReturnsTheResultWhenTheOperationIsFast()
    {
        var result = await SemanticDeadline.RunAsync(TimeSpan.FromSeconds(5), "fallback", _ => Task.FromResult("done"));
        Assert.Equal("done", result);
    }

    [Fact]
    public async Task DeadlineReturnsTheFallbackAndCancelsTheLoser()
    {
        var observed = new TaskCompletionSource<bool>();
        var result = await SemanticDeadline.RunAsync(TimeSpan.FromMilliseconds(50), "fallback", async token =>
        {
            try
            {
                await Task.Delay(Timeout.Infinite, token);
            }
            catch (OperationCanceledException)
            {
                observed.SetResult(true);
                throw;
            }

            return "late";
        });
        Assert.Equal("fallback", result);
        Assert.True(await observed.Task.WaitAsync(TimeSpan.FromSeconds(5)));
    }

    [Fact]
    public async Task DeadlineIsNotDelayedByUncancellableWork()
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        var result = await SemanticDeadline.RunAsync(TimeSpan.FromMilliseconds(100), -1, _ =>
        {
            Thread.Sleep(1500);
            return Task.FromResult(1);
        });
        Assert.Equal(-1, result);
        Assert.True(watch.Elapsed < TimeSpan.FromMilliseconds(1000), $"took {watch.Elapsed}");
    }

    [Fact]
    public async Task DeadlineHonoursCallerCancellationWithTheFallback()
    {
        using var cancel = new CancellationTokenSource();
        var running = SemanticDeadline.RunAsync(TimeSpan.FromSeconds(30), "fallback", token => Task.Delay(Timeout.Infinite, token).ContinueWith(_ => "late", CancellationToken.None), cancel.Token);
        await cancel.CancelAsync();
        Assert.Equal("fallback", await running.WaitAsync(TimeSpan.FromSeconds(5)));
    }

    [Fact]
    public async Task OnlyTheLatestPendingQueryRunsAfterTheActiveOneDrains()
    {
        var queue = new LatestQueryQueue();
        var release = new TaskCompletionSource();
        var started = new TaskCompletionSource();
        var ran = new List<string>();

        var first = queue.SubmitAsync(async _ =>
        {
            lock (ran)
            {
                ran.Add("first");
            }

            started.SetResult();
            await release.Task;
            return [1f];
        });
        await started.Task;
        var second = queue.SubmitAsync(_ => Record(ran, "second", 2f));
        var third = queue.SubmitAsync(_ => Record(ran, "third", 3f));

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => first);
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => second);
        release.SetResult();
        Assert.Equal(new[] { 3f }, await third.WaitAsync(TimeSpan.FromSeconds(5)));
        lock (ran)
        {
            Assert.Equal(new[] { "first", "third" }, ran);
        }
    }

    [Fact]
    public async Task CancellingAPendingQueryNeverRunsIt()
    {
        var queue = new LatestQueryQueue();
        var release = new TaskCompletionSource();
        var started = new TaskCompletionSource();
        var ran = false;
        var active = queue.SubmitAsync(async _ =>
        {
            started.SetResult();
            await release.Task;
            return [1f];
        });
        await started.Task;
        using var cancel = new CancellationTokenSource();
        var pending = queue.SubmitAsync(_ =>
        {
            ran = true;
            return Task.FromResult(new[] { 2f });
        }, cancel.Token);
        await cancel.CancelAsync();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pending);
        release.SetResult();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => active);
        // A later query still gets served.
        Assert.Equal(new[] { 9f }, await queue.SubmitAsync(_ => Task.FromResult(new[] { 9f })).WaitAsync(TimeSpan.FromSeconds(5)));
        Assert.False(ran);
    }

    private static Task<float[]> Record(List<string> ran, string name, float value)
    {
        lock (ran)
        {
            ran.Add(name);
        }

        return Task.FromResult(new[] { value });
    }
}
