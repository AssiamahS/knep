import Network
import Foundation

class KnepConnectionManager: ObservableObject {
    @Published var isConnected = false
    @Published var statusMessage = "Searching for Mac…"

    let videoDecoder = VideoDecoder()

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var buffer = Data()
    private let ioQueue = DispatchQueue(label: "knep.io", qos: .userInteractive)

    func start() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_knep._tcp", domain: nil), using: params)

        browser?.stateUpdateHandler = { [weak self] state in
            if case .failed(let err) = state {
                DispatchQueue.main.async { self?.statusMessage = "Search error — retrying…" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.start() }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            // Take the first knep service found
            if let endpoint = results.first(where: {
                if case .service(let name, let type, _, _) = $0.endpoint { return type.contains("_knep") }
                return false
            })?.endpoint ?? results.first?.endpoint {
                self?.browser?.cancel()
                self?.connect(to: endpoint)
            }
        }

        browser?.start(queue: ioQueue)
        DispatchQueue.main.async { self.statusMessage = "Searching for Mac…" }
    }

    private func connect(to endpoint: NWEndpoint) {
        DispatchQueue.main.async { self.statusMessage = "Connecting…" }

        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let conn = NWConnection(to: endpoint, using: params)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async { self.isConnected = true; self.statusMessage = "Connected" }
                self.receive()
            case .failed(let err):
                DispatchQueue.main.async { self.isConnected = false; self.statusMessage = "Lost connection — retrying…" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.buffer = Data(); self.start() }
            case .cancelled:
                DispatchQueue.main.async { self.isConnected = false }
            default: break
            }
        }

        conn.start(queue: ioQueue)
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drain()
            }
            if error == nil && !isComplete {
                self.receive()
            }
        }
    }

    private func drain() {
        while buffer.count >= 5 {
            let payloadLen = Int(buffer.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            let msgType   = buffer[4]
            let needed    = 5 + payloadLen
            guard buffer.count >= needed else { break }

            let payload = buffer.subdata(in: 5..<needed)
            buffer.removeFirst(needed)
            handle(type: msgType, payload: payload)
        }
    }

    private func handle(type: UInt8, payload: Data) {
        switch type {
        case 0x01: videoDecoder.receiveFormatData(payload)
        case 0x02: videoDecoder.receiveVideoFrame(payload)
        default: break
        }
    }
}
