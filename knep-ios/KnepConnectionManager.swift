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
        browser?.cancel()
        browser = nil

        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_knep2._tcp", domain: nil), using: params)
        browser = b

        b.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed:
                DispatchQueue.main.async { self?.statusMessage = "Search error — retrying…" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.start() }
            case .waiting:
                DispatchQueue.main.async { self?.statusMessage = "Network unavailable — retrying…" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.start() }
            default: break
            }
        }

        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            if let endpoint = results.first(where: {
                if case .service(_, let type, _, _) = $0.endpoint { return type.contains("_knep2") }
                return false
            })?.endpoint ?? results.first?.endpoint {
                self.browser?.cancel()
                self.browser = nil
                self.connect(to: endpoint)
            }
        }

        b.start(queue: ioQueue)

        // Restart if no service found within 5 seconds
        ioQueue.asyncAfter(deadline: .now() + 5) { [weak self, weak b] in
            guard let self, self.browser === b, !self.isConnected else { return }
            self.start()
        }

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
                self.ioQueue.async { self.buffer = Data() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.start() }
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
        // Data keeps non-zero startIndex after removeFirst — never use absolute
        // offsets. Walk with indices relative to startIndex, trim once at the end.
        var offset = buffer.startIndex
        while buffer.endIndex - offset >= 5 {
            let payloadLen = Int(UInt32(bigEndian:
                buffer[offset..<offset + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
            let msgType = buffer[offset + 4]
            let needed  = 5 + payloadLen
            guard buffer.endIndex - offset >= needed else { break }

            // Copy rebases indices to 0 for downstream parsers.
            let payload = Data(buffer[(offset + 5)..<(offset + needed)])
            offset += needed
            handle(type: msgType, payload: payload)
        }
        buffer.removeSubrange(buffer.startIndex..<offset)
    }

    private func handle(type: UInt8, payload: Data) {
        switch type {
        case 0x01: videoDecoder.receiveFormatData(payload)
        case 0x02: videoDecoder.receiveVideoFrame(payload)
        default: break
        }
    }
}
