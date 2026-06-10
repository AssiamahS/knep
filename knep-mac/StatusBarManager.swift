import Cocoa

extension Notification.Name {
    static let knepClientConnected = Notification.Name("knepClientConnected")
    static let knepClientDisconnected = Notification.Name("knepClientDisconnected")
}

class StatusBarManager {
    private var statusItem: NSStatusItem
    private let server: KnepServer

    init(server: KnepServer) {
        self.server = server
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "knep")
        }

        buildMenu()

        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .knepClientConnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .knepClientDisconnected, object: nil)
    }

    private func buildMenu() {
        let menu = NSMenu()

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let titleItem = NSMenuItem(title: "knep  v\(version)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let statusItem = NSMenuItem(title: "Waiting for iPhone…", action: nil, keyEquivalent: "")
        statusItem.tag = 1
        menu.addItem(statusItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        self.statusItem.menu = menu
    }

    @objc private func refresh() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let item = self.statusItem.menu?.item(withTag: 1) else { return }
            let count = self.server.connectedCount
            item.title = count > 0 ? "Connected (\(count) device\(count == 1 ? "" : "s"))" : "Waiting for iPhone…"
        }
    }
}
