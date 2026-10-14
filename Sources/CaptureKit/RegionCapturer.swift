import Foundation

public struct RegionCapture: Equatable, Sendable {
    public let pngData: Data
    public let context: FrontmostContext
}

public enum RegionCaptureResult: Equatable, Sendable {
    case captured(RegionCapture)
    case cancelled
    case permissionNeeded
}

public enum RegionCaptureError: Error, Equatable, Sendable {
    case processFailed(status: Int32)
}

@MainActor
public enum RegionCapturer {
    /// Does not request permission or activate the app. Capture the context at hotkey entry
    /// and pass it here when launching from an asynchronously scheduled task.
    public static func capture(context suppliedContext: FrontmostContext? = nil) async throws -> RegionCaptureResult {
        let context = suppliedContext ?? FrontmostContext.capture()
        guard CapturePermissions.screenCaptureAllowed else { return .permissionNeeded }
        guard !Task.isCancelled else { return .cancelled }
        return try await performCapture(context: context)
    }

    @concurrent
    private static func performCapture(context: FrontmostContext) async throws -> RegionCaptureResult {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("region.png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-t", "png", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do { try process.run() }
            catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        // Apple's selection UI exits without creating a file when the user presses Escape.
        guard FileManager.default.fileExists(atPath: file.path) else { return .cancelled }
        guard status == 0 else { throw RegionCaptureError.processFailed(status: status) }
        guard !Task.isCancelled else { return .cancelled }
        return .captured(RegionCapture(pngData: try Data(contentsOf: file), context: context))
    }
}
