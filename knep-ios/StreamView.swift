import SwiftUI
import AVFoundation
import UIKit
import CoreMedia

final class StreamDisplayView: UIView {
    private let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer.frame = bounds
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        let renderer = displayLayer.sampleBufferRenderer
        // The renderer silently dies after backgrounding or a decode error and
        // ignores everything until flushed — this is the "black screen until
        // force-quit" failure mode.
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            renderer.flush()
        }
        renderer.enqueue(sampleBuffer)
    }

    func flush() {
        displayLayer.sampleBufferRenderer.flush()
    }
}

struct StreamView: UIViewRepresentable {
    let decoder: VideoDecoder

    func makeUIView(context: Context) -> StreamDisplayView {
        let view = StreamDisplayView()
        decoder.streamView = view
        return view
    }

    func updateUIView(_ uiView: StreamDisplayView, context: Context) {}
}
