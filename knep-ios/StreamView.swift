import SwiftUI
import AVFoundation
import UIKit

final class StreamDisplayView: UIView {
    // iOS 16 fallback
    private let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        displayLayer.frame = bounds
        layer.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sampleBuffer)
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
