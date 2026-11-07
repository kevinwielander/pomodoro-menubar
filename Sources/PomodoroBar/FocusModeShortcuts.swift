import Foundation

/// macOS has no public API for Focus, so the app runs two user-created
/// Shortcuts through the `shortcuts` command line tool.
enum FocusModeShortcuts {
    static let onName = "PomodoroBar Focus On"
    static let offName = "PomodoroBar Focus Off"
    static let names = [onName, offName]

    private static let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")
    /// `shortcuts run` sometimes fails or hangs when started right after
    /// another run, so runs never overlap and each gets a timeout and a retry.
    private static let queue = DispatchQueue(label: "PomodoroBar.FocusModeShortcuts")
    private static let timeout: TimeInterval = 10

    /// Runs off the main thread; `completion` gets an error message, or nil on success.
    static func set(enabled: Bool, completion: @escaping @Sendable (String?) -> Void = { _ in }) {
        let name = enabled ? onName : offName
        queue.async {
            var error = runShortcut(name)
            if error != nil {
                Thread.sleep(forTimeInterval: 1)
                error = runShortcut(name)
            }
            completion(error)
        }
    }

    /// Blocks until done, for use while the app is quitting.
    static func disableSynchronously() {
        queue.sync { _ = runShortcut(offName) }
    }

    /// Names of the required shortcuts that do not exist yet.
    static func missing(completion: @escaping @Sendable ([String]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let existing = Set(list().split(separator: "\n").map(String.init))
            completion(names.filter { !existing.contains($0) })
        }
    }

    private static func process(_ arguments: [String]) -> (Process, stdout: Pipe, stderr: Pipe) {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        return (process, stdout, stderr)
    }

    private static func list() -> String {
        let (process, stdout, _) = process(["list"])
        guard (try? process.run()) != nil else { return "" }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Returns nil on success, otherwise a message for the settings screen.
    private static func runShortcut(_ name: String) -> String? {
        let (process, _, stderr) = process(["run", name])
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return "Couldn't start the shortcuts tool: \(error.localizedDescription)"
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return "The shortcut “\(name)” didn't finish within \(Int(timeout)) seconds."
        }
        guard process.terminationStatus != 0 else { return nil }
        let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "Couldn't run the shortcut “\(name)”" + (message.isEmpty ? "." : ": \(message)")
    }
}
