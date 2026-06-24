import XCTest
import AVFoundation
import CoreVideo
import CoreGraphics
import MediaMeasure
@testable import EraseKit

final class VideoEraserTests: XCTestCase {
    /// Echoes the mask back as the "filled" image, so a test can read which mask was used each frame.
    private struct MaskEcho: InpaintProvider {
        let name = "echo"
        func inpaint(_ image: CGImage, mask: CGImage, quality: InpaintQuality) async throws -> CGImage { mask }
    }
    /// Flat solid-colour fill (size-preserving) — stands in for a real inpainter for the e2e run.
    private struct FlatFill: InpaintProvider {
        let name = "flat"
        func inpaint(_ image: CGImage, mask: CGImage, quality: InpaintQuality) async throws -> CGImage {
            var px = [UInt8](repeating: 0, count: image.width * image.height * 4)
            for i in 0..<(image.width * image.height) { px[i*4+2] = 200; px[i*4+3] = 255 }
            return CGContext(data: &px, width: image.width, height: image.height, bitsPerComponent: 8,
                             bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
    }

    private func grayFrame(_ w: Int, _ h: Int) -> CGImage {
        var b = [UInt8](repeating: 30, count: w * h)
        return CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!.makeImage()!
    }
    private func maskRect(_ rx: Int, _ ry: Int, _ rw: Int, _ rh: Int, _ w: Int, _ h: Int) -> CGImage {
        var b = [UInt8](repeating: 0, count: w * h)
        for y in ry..<(ry + rh) { for x in rx..<(rx + rw) { b[y * w + x] = 255 } }
        return CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!.makeImage()!
    }
    private func grayByte(_ cg: CGImage, _ x: Int, _ y: Int) -> UInt8 {
        let w = cg.width, h = cg.height
        var b = [UInt8](repeating: 0, count: w * h)
        CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            .draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return b[y * w + x]
    }
    private static func constFlow(_ u: Float, _ v: Float, _ w: Int, _ h: Int) -> DenseFlow {
        var uv = [Float](repeating: 0, count: w * h * 2)
        for p in 0..<(w * h) { uv[p * 2] = u; uv[p * 2 + 1] = v }
        return DenseFlow(width: w, height: h, uv: uv)
    }

    /// The painted mask tracks the subject: under a constant cur→prev flow of u=+6, the propagated mask
    /// backward-warps (samples prevMask at x+6) → the masked square shifts ~6px left frame-to-frame.
    func testMaskPropagatesWithFlow() async throws {
        let w = 24, h = 24
        let prop = MaskPropagator(initialMask: maskRect(10, 10, 4, 4, w, h), provider: MaskEcho(),
                                  quality: .best, dilation: 0, flow: { a, _ in Self.constFlow(6, 0, a.width, a.height) })
        let frame = grayFrame(w, h)
        let m0 = try await prop.next(frame)
        let m1 = try await prop.next(frame)
        XCTAssertGreaterThan(grayByte(m0, 11, 11), 200, "frame 0: painted square present at x≈10–13")
        XCTAssertGreaterThan(grayByte(m1, 5, 11), 200, "frame 1: mask tracked ~6px left")
        XCTAssertLessThan(grayByte(m1, 11, 11), 60, "frame 1: old position vacated (mask moved, didn't stay static)")
    }

    /// No flow → the mask stays static (degrades to non-tracking, doesn't crash).
    func testNoFlowKeepsMaskStatic() async throws {
        let w = 24, h = 24
        let prop = MaskPropagator(initialMask: maskRect(10, 10, 4, 4, w, h), provider: MaskEcho(),
                                  quality: .best, dilation: 0, flow: nil)
        let frame = grayFrame(w, h)
        _ = try await prop.next(frame)
        let m1 = try await prop.next(frame)
        XCTAssertGreaterThan(grayByte(m1, 11, 11), 200, "static mask stays put")
    }

    private func makeClip(at url: URL, w: Int, h: Int, frames: Int) throws {
        let fps = 30
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { usleep(500) }
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, nil, &pb)
            let buf = pb!
            CVPixelBufferLockBaseAddress(buf, [])
            if let base = CVPixelBufferGetBaseAddress(buf) {
                let p = base.assumingMemoryBound(to: UInt8.self)
                var s = UInt32(truncatingIfNeeded: i &* 2654435761 | 1)
                for j in 0..<(CVPixelBufferGetBytesPerRow(buf) * h) { s = s &* 1664525 &+ 1013904223; p[j] = UInt8(truncatingIfNeeded: s >> 16) }
            }
            CVPixelBufferUnlockBaseAddress(buf, [])
            adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0); writer.finishWriting { sem.signal() }; sem.wait()
    }

    /// e2e: read clip → per-frame inpaint (stub) with the propagated mask → opaque HEVC, dims preserved.
    func testEraseVideoEndToEnd() async throws {
        let w = 64, h = 48
        let inURL = FileManager.default.temporaryDirectory.appendingPathComponent("ve-in-\(UUID()).mp4")
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("ve-out-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: inURL); try? FileManager.default.removeItem(at: outURL) }
        try makeClip(at: inURL, w: w, h: h, frames: 5)

        let written = try await VideoEraser.eraseVideo(
            input: inURL, output: outURL, initialMask: maskRect(20, 16, 16, 16, w, h),
            provider: FlatFill(), dilation: 4, flow: nil)
        XCTAssertEqual(written, 5)

        let asset = AVURLAsset(url: outURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(Int(size.width.rounded()), w); XCTAssertEqual(Int(size.height.rounded()), h)
    }
}
