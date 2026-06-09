import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarManager: StatusBarManager?
    let server = KnepServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarManager = StatusBarManager(server: server)
        server.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
    }
}
