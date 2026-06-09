import Network
import Foundation

class KnepServer {
    private var listener: NWListener?
    private var connections: [KnepConnection] = []
    private let queue = DispatchQueue(label: "knep.server", qos: .userInteractive)
    private var captureManager: ScreenCaptureManager?

    var connectedCount: Int { connections.count }

    func start() {
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true

            listener = try NWListener(using: params, on: 12345)
            listener?.service = NWListener.Service(name: "knep", type: "_knep._tcp")

            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready: print("[server] listening on :12345")
                case .failed(let err): print("[server] failed: \(err)")
                default: break
                }
            }

            listener?.newConnectionHandler = { [weak self] conn in
                self?.queue.async { self?.accept(conn) }
            }

            listener?.start(queue: queue)
        } catch {
            print("[server] could not start: \(error)")
        }
    }

    private func accept(_ nwConn: NWConnection) {
        let conn = KnepConnection(nwConnection: nwConn)
        connections.append(conn)

        conn.onDisconnect = { [weak self] in
            self?.queue.async {
                self?.connections.removeAll { $0 === conn }
                NotificationCenter.default.post(name: .knepClientDisconnected, object: nil)
                if self?.connections.isEmpty == true {
                    self?.captureManager?.stop()
                    self?.captureManager = nil
                }
            }
        }

        conn.start()
        NotificationCenter.default.post(name: .knepClientConnected, object: nil)

        // Start capture on first connection
        if captureManager == nil {
            let mgr = ScreenCaptureManager()
            mgr.onFrame = { [weak self] type, data in
                self?.queue.async { self?.broadcast(type: type, data: data) }
            }
            captureManager = mgr
            mgr.start()
        }
    }

    private func broadcast(type: UInt8, data: Data) {
        for conn in connections {
            conn.send(type: type, payload: data)
        }
    }

    func stop() {
        listener?.cancel()
        connections.forEach { $0.cancel() }
        captureManager?.stop()
    }
}

// MARK: - Single client connection

final class KnepConnection {
    private let nwConn: NWConnection
    var onDisconnect: (() -> Void)?
    private var sendPending = false

    init(nwConnection: NWConnection) {
        self.nwConn = nwConnection
    }

    func start() {
        nwConn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[conn] client ready")
            case .failed(let err), .waiting(let err):
                print("[conn] lost: \(err)")
                self?.onDisconnect?()
            case .cancelled:
                self?.onDisconnect?()
            default: break
            }
        }
        nwConn.start(queue: .global(qos: .userInteractive))
    }

    func send(type: UInt8, payload: Data) {
        guard !sendPending else { return } // drop if backpressured
        sendPending = true

        var header = Data(count: 5)
        let len = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: len) { header.replaceSubrange(0..<4, with: $0) }
        header[4] = type

        nwConn.send(content: header + payload, completion: .contentProcessed { [weak self] _ in
            self?.sendPending = false
        })
    }

    func cancel() { nwConn.cancel() }
}
