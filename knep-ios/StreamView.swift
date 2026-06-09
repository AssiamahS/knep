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
        displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)
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
