import AppKit
import Core
import Darwin
import os

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--self-test" {
    do {
        guard arguments.count == 2 || (arguments.count == 4 && arguments[2] == "--models") else {
            throw SelfTestFailure("Usage: --self-test <dir> [--models <dir>]")
        }
        let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let models = arguments.count == 4 ? URL(fileURLWithPath: arguments[3], isDirectory: true) : nil
        let pipeline = try await CapturePipeline.open(vaultRoot: directory, stateDirectory: directory, calendar: .current, modelsDirectory: models)
        let controller = AppController(pipeline: pipeline, presentsUI: false)
        print(try await controller.runSelfTest())
        exit(EXIT_SUCCESS)
    } catch {
        fputs("Self-test failed: \(error)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "startup")
logger.notice("Started \(AppInfo.name, privacy: .public) with SQLite \(SQLiteVersion.string, privacy: .public)")

let delegate = ApplicationDelegate()
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
