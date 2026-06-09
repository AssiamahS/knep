import SwiftUI
import AVFoundation
import UIKit

final class StreamDisplayView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }
}

struct StreamView: UIViewRepresentable {
    let decoder: VideoDecoder

    func makeUIView(context: Context) -> StreamDisplayView {
        let view = StreamDisplayView()
        decoder.displayLayer = view.displayLayer
        return view
    }

    func updateUIView(_ uiView: StreamDisplayView, context: Context) {}
}
