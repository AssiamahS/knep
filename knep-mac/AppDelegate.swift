import Cocoa
import ScreenCaptureKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarManager: StatusBarManager?
    let server = KnepServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarManager = StatusBarManager(server: server)
        server.start()
        // Warm up SCK at launch so macOS prompts for Screen Recording immediately
        Task {
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
    }
}
