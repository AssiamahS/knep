import VideoToolbox
import CoreMedia
import CoreVideo

class VideoEncoder {
    private var session: VTCompressionSession?
    private let width: Int
    private let height: Int
    private var isFirstFrame = true

    var onEncodedFrame: ((UInt8, Data) -> Void)?

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    func setup() {
        let spec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true
        ]

        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: VideoEncoder.outputCB,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )

        guard status == noErr, let session else {
            print("[encoder] create failed: \(status)")
            return
        }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 8_000_000 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 60 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTCompressionSessionPrepareToEncodeFrames(session)
        print("[encoder] ready \(width)×\(height)")
    }

    func encode(pixelBuffer: CVImageBuffer, pts: CMTime) {
        guard let session else { return }

        let props: CFDictionary? = isFirstFrame
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
            : nil
        isFirstFrame = false

        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: .invalid,
            frameProperties: props,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    private static let outputCB: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
        guard status == noErr, let sampleBuffer, let refcon else { return }
        Unmanaged<VideoEncoder>.fromOpaque(refcon).takeUnretainedValue()
            .handleOutput(sampleBuffer)
    }

    private func handleOutput(_ sampleBuffer: CMSampleBuffer) {
        // Determine keyframe
        var isKeyFrame = true
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false),
           CFArrayGetCount(arr) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: NSDictionary.self)
            isKeyFrame = !(dict[kCMSampleAttachmentKey_NotSync as String] as? Bool ?? false)
        }

        // Send SPS/PPS before every keyframe so the decoder can re-sync
        if isKeyFrame,
           let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
           let paramData = extractParams(formatDesc) {
            onEncodedFrame?(0x01, paramData)
        }

        // Send AVCC frame data
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let totalLen = CMBlockBufferGetDataLength(block)
        guard totalLen > 0 else { return }
        var frameData = Data(count: totalLen)
        let status = frameData.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: totalLen, destination: $0.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else { return }
        onEncodedFrame?(0x02, frameData)
    }

    private func extractParams(_ desc: CMVideoFormatDescription) -> Data? {
        var spsPtr: UnsafePointer<UInt8>?; var spsLen = 0
        var ppsPtr: UnsafePointer<UInt8>?; var ppsLen = 0

        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            desc, parameterSetIndex: 0,
            parameterSetPointerOut: &spsPtr, parameterSetSizeOut: &spsLen,
            parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            desc, parameterSetIndex: 1,
            parameterSetPointerOut: &ppsPtr, parameterSetSizeOut: &ppsLen,
            parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)

        guard let sps = spsPtr, spsLen > 0, let pps = ppsPtr, ppsLen > 0 else { return nil }

        var out = Data()
        var l: UInt32
        l = UInt32(spsLen).bigEndian; out.append(Data(bytes: &l, count: 4))
        out.append(Data(bytes: sps, count: spsLen))
        l = UInt32(ppsLen).bigEndian; out.append(Data(bytes: &l, count: 4))
        out.append(Data(bytes: pps, count: ppsLen))
        return out
    }
}
