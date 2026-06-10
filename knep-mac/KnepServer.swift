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
            // Nagle holds small frame packets up to ~200ms each — kills typing
            // latency over WiFi. Flush every send immediately.
            if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
                tcp.noDelay = true
            }

            listener = try NWListener(using: params, on: 12345)
            listener?.service = NWListener.Service(name: "knep", type: "_knep2._tcp")

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

        conn.onBacklogDrained = { [weak self] in
            self?.queue.async { self?.captureManager?.resendKeyFrame() }
        }

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
        } else {
            // Capture already running (reconnect, or a stale conn kept it alive):
            // give the new client an immediate keyframe to decode from.
            captureManager?.resendKeyFrame()
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
    // Fired after the backlog drains following overflow drops, so the server
    // can push a fresh keyframe — without it the client shows a frozen frame
    // until the screen happens to produce the next scheduled keyframe.
    var onBacklogDrained: (() -> Void)?
    private let sendQueue = DispatchQueue(label: "knep.conn.send", qos: .userInteractive)
    private var pending: [Data] = []
    private var sending = false
    private var droppedSinceDrain = false
    // Keep the backlog short so latency can't accumulate — stale frames are
    // worse than dropped ones for interactive use. Heavy motion (Space-switch
    // animations) overflows this; the drain callback above recovers the picture.
    private let maxPending = 20

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
        var header = Data(count: 5)
        let len = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: len) { header.replaceSubrange(0..<4, with: $0) }
        header[4] = type
        let msg = header + payload

        // Never drop individual messages mid-stream — the 0x01 param set and its
        // 0x02 keyframe arrive back-to-back and both must reach the decoder.
        sendQueue.async { [weak self] in
            guard let self else { return }
            guard self.pending.count < self.maxPending else {
                self.droppedSinceDrain = true
                return
            }
            self.pending.append(msg)
            self.pump()
        }
    }

    private func pump() {
        guard !sending, !pending.isEmpty else { return }
        sending = true
        let msg = pending.removeFirst()
        nwConn.send(content: msg, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.sendQueue.async {
                if error != nil {
                    // Dead peer (app swipe-killed, network switch) — reap the
                    // connection instead of pumping into a void forever.
                    self.pending.removeAll()
                    self.nwConn.cancel()
                    self.onDisconnect?()
                    return
                }
                self.sending = false
                if self.pending.isEmpty, self.droppedSinceDrain {
                    self.droppedSinceDrain = false
                    self.onBacklogDrained?()
                }
                self.pump()
            }
        })
    }

    func cancel() { nwConn.cancel() }
}
