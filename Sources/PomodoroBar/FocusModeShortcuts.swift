import Foundation

/// macOS has no public API for Focus, so the app runs two user-created
/// Shortcuts through the `shortcuts` command line tool.
enum FocusModeShortcuts {
    static let onName = "PomodoroBar Focus On"
    static let offName = "PomodoroBar Focus Off"
    static let names = [onName, offName]

    private static let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")

    /// Runs off the main thread; `completion` gets whether the shortcut succeeded.
    static func set(enabled: Bool, completion: @escaping @Sendable (Bool) -> Void = { _ in }) {
        let name = enabled ? onName : offName
        DispatchQueue.global(qos: .userInitiated).async {
            completion(run(["run", name]).status == 0)
        }
    }

    /// Blocks until done, for use while the app is quitting.
    static func disableSynchronously() {
        _ = run(["run", offName])
    }

    /// Names of the required shortcuts that do not exist yet.
    static func missing(completion: @escaping @Sendable ([String]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let existing = Set(run(["list"]).output.split(separator: "\n").map(String.init))
            completion(names.filter { !existing.contains($0) })
        }
    }

    private static func run(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
