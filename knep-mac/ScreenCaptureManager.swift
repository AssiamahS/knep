import ScreenCaptureKit
import CoreMedia
import AVFoundation
import CoreGraphics

class ScreenCaptureManager: NSObject {
    var onFrame: ((UInt8, Data) -> Void)?
    private var stream: SCStream?
    private var encoder: VideoEncoder?

    func start() {
        Task { await setup() }
    }

    private func setup() async {
        guard CGRequestScreenCaptureAccess() else {
            await MainActor.run { showPermissionAlert() }
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }

            // Cap at 1920×1080 to keep bitrate sane over the connection
            let w = min(display.width, 1920)
            let h = min(display.height, 1080)

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
            print("[capture] started \(w)×\(h) @ 30fps")
        } catch {
            print("[capture] error: \(error)")
        }
    }

    func stop() {
        let s = stream
        stream = nil
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
