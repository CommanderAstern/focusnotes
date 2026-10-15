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

@_spi(Testing)
public enum RegionCaptureProcessDisposition: Equatable, Sendable {
    case cancelled
    case captured
    case failed(status: Int32)
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

    /// Keeps the documented Escape path distinct from a failed screencapture process.
    @_spi(Testing)
    nonisolated public static func processDisposition(status: Int32, outputExists: Bool) -> RegionCaptureProcessDisposition {
        guard status == 0 else { return .failed(status: status) }
        return outputExists ? .captured : .cancelled
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
        switch processDisposition(status: status, outputExists: FileManager.default.fileExists(atPath: file.path)) {
        case .cancelled:
            return .cancelled
        case .failed(let status):
            throw RegionCaptureError.processFailed(status: status)
        case .captured:
            break
        }
        guard !Task.isCancelled else { return .cancelled }
        return .captured(RegionCapture(pngData: try Data(contentsOf: file), context: context))
    }
}
