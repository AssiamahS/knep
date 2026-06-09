import VideoToolbox
import AVFoundation
import CoreMedia
import CoreVideo

class VideoDecoder {
    var displayLayer: AVSampleBufferDisplayLayer?
    private var formatDescription: CMVideoFormatDescription?

    // Type 0x01 payload: [4-byte BE SPS len][SPS][4-byte BE PPS len][PPS]
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
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil, parameterSetCount: 2,
                    parameterSetPointers: ptrs, parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &desc
                )
                self.formatDescription = desc
            }
        }
    }

    // Type 0x02 payload: raw AVCC H.264 data (NAL units with 4-byte length prefixes)
    func receiveVideoFrame(_ data: Data) {
        guard let formatDesc = formatDescription else { return }

        // Allocate owned memory for the block buffer
        let count = data.count
        let mem = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        data.copyBytes(to: mem, count: count)

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: mem, blockLength: count,
            blockAllocator: kCFAllocatorDefault,  // CMBlockBuffer owns + will free
            customBlockSource: nil, offsetToData: 0, dataLength: count,
            flags: 0, blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr, let block = blockBuffer else {
            mem.deallocate()
            return
        }

        var sampleSize = count
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: block, formatDescription: formatDesc,
            sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sample = sampleBuffer else { return }

        // Mark for immediate display (no presentation-time scheduling)
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(arr) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        DispatchQueue.main.async { [weak self] in
            guard let layer = self?.displayLayer else { return }
            if layer.status == .failed { layer.flush() }
            layer.enqueue(sample)
        }
    }
}
