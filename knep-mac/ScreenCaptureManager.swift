import ScreenCaptureKit
import CoreMedia
import AVFoundation
import CoreGraphics

class ScreenCaptureManager: NSObject {
    var onFrame: ((UInt8, Data) -> Void)?
    private var stream: SCStream?
    private var encoder: VideoEncoder?

    private func slog(_ msg: String) {
        NSLog("[knep] \(msg)")
        let line = "\(Date()): \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        let path = "/tmp/knep_sck.log"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile(); fh.write(data); try? fh.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    func start() {
        slog("start() called")
        Task { await setup() }
    }

    private func setup() async {
        slog("setup() running")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                slog("no displays found")
                return
            }

            let w = min(display.width, 1920)
            let h = min(display.height, 1080)
            slog("capture starting \(w)x\(h)")

            let enc = VideoEncoder(width: w, height: h)
            enc.onEncodedFrame = { [weak self] type, data in self?.onFrame?(type, data) }
            enc.setup()
            encoder = enc

            let config = SCStreamConfiguration()
            config.width = w
            config.height = h
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.queueDepth = 3
            config.pixelFormat = kCVPixelFormatType_32BGRA

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
            try await s.startCapture()
            stream = s
            slog("capture running \(w)x\(h) @ 30fps")
        } catch {
            slog("capture error: \(error)")
            let msg = "\(error)"
            if msg.contains("TCCDenied") || msg.contains("permissionDenied") || msg.contains("1108") || msg.contains("3801") {
                await MainActor.run { showPermissionAlert() }
            }
        }
    }

    func stop() {
        let s = stream
        stream = nil
        encoder?.stop()
        encoder = nil
        Task { try? await s?.stopCapture() }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Open System Settings → Privacy & Security → Screen Recording and enable knep, then relaunch."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }
}

extension ScreenCaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[capture] stream stopped: \(error)")
    }
}

extension ScreenCaptureManager: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        encoder?.encode(pixelBuffer: pixelBuffer, pts: pts)
    }
}
