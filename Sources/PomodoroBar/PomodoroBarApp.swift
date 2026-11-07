import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        // `PomodoroBar --screenshots <dir>` renders the README screenshots and exits.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--screenshots"), arguments.indices.contains(index + 1) {
            MainActor.assumeIsolated {
                ScreenshotRenderer.render(to: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
            }
            return
        }
        PomodoroBarApp.main()
    }
}

struct PomodoroBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = TimerController()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(controller)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The bundle sets LSUIElement; this also hides the Dock icon under `swift run`.
        NSApp.setActivationPolicy(.accessory)
    }
}
