import VideoToolbox
import AVFoundation
import CoreMedia
import CoreVideo

class VideoDecoder {
    var streamView: StreamDisplayView?
    private var formatDescription: CMVideoFormatDescription?

    func reset() {
        formatDescription = nil
        DispatchQueue.main.async { [weak self] in self?.streamView?.flush() }
    }

    func receiveFormatData(_ data: Data) {
        guard data.count > 8 else { return }
        var offset = 0

        let spsLen = Int(data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        offset += 4
        guard data.count >= offset + spsLen else { return }
        let spsData = data.subdata(in: offset..<offset + spsLen)
        offset += spsLen

        guard data.count >= offset + 4 else { return }
        let ppsLen = Int(data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        offset += 4
        guard data.count >= offset + ppsLen else { return }
        let ppsData = data.subdata(in: offset..<offset + ppsLen)

        spsData.withUnsafeBytes { spsBuf in
            ppsData.withUnsafeBytes { ppsBuf in
                let ptrs: [UnsafePointer<UInt8>] = [
                    spsBuf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    ppsBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                ]
                let sizes = [spsLen, ppsLen]
                var desc: CMVideoFormatDescription?
                let st = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil, parameterSetCount: 2,
                    parameterSetPointers: ptrs, parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &desc
                )
                if st == noErr { self.formatDescription = desc }
            }
        }
    }

    func receiveVideoFrame(_ data: Data) {
        guard let formatDesc = formatDescription, !data.isEmpty else { return }

        // CMBlockBuffer owns its own memory allocation — no manual pointer management.
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr, let block = blockBuffer else { return }

        let copyStatus = data.withUnsafeBytes { ptr in
            CMBlockBufferReplaceDataBytes(with: ptr.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copyStatus == kCMBlockBufferNoErr else { return }

        // Provide a valid PTS so AVSampleBufferVideoRenderer can schedule the frame.
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleSize = data.count
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: block, formatDescription: formatDesc,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sample = sampleBuffer else { return }

        // Mark for immediate display (bypass renderer clock scheduling).
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(arr) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: NSMutableDictionary.self)
            dict[kCMSampleAttachmentKey_DisplayImmediately as NSString] = kCFBooleanTrue
        }

        DispatchQueue.main.async { [weak self] in
            self?.streamView?.enqueue(sample)
        }
    }
}
