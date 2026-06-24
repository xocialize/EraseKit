import CoreGraphics
import Foundation
import MediaMeasure

/// **Video object removal** — per-frame inpaint with a **flow-propagated mask** so a single painted mask tracks
/// a *moving* subject. The interim before EdgeTAM masklet tracking (deferred to pro): the user paints the mask
/// once (frame 0); each subsequent frame backward-warps that mask along the SEA-RAFT flow (the same FlowWarp the
/// matting/upscale paths use) so it follows the subject, then re-thresholds (keep it binary), dilates (full
/// coverage + margin), and inpaints. Net-clean: the inpaint + flow models inject as closures.
///
/// Limitations (honest): the warped mask **drifts** over long clips (errors compound — that's what EdgeTAM
/// fixes), and a static-flow fallback (nil flow) degrades to a non-tracking mask. The FILL is computed
/// per-frame (no cross-frame blend — blending would smear the moving subject; fill-region temporal stability
/// is a separate follow-up).
public enum VideoEraser {
    /// Erase the subject under `initialMask` (painted on frame 0) across `input` → opaque HEVC at `output`.
    /// Returns frames written. `flow` = the SEA-RAFT seam (nil → mask doesn't track).
    @discardableResult
    public static func eraseVideo(
        input: URL, output: URL,
        initialMask: CGImage,
        provider: (any InpaintProvider)?,
        quality: InpaintQuality = .best,
        dilation: Int = 8,
        flow: (@Sendable (CGImage, CGImage) async throws -> DenseFlow)? = nil,
        codecQuality: Float = 0.9
    ) async throws -> Int {
        let prop = MaskPropagator(initialMask: initialMask, provider: provider, quality: quality,
                                  dilation: max(0, dilation), flow: flow)
        return try await VideoFrameMap.mapToVideo(input: input, output: output, quality: codecQuality) {
            try await prop.next($0)
        }
    }
}

/// Stateful per-frame erase: carries the previous frame + the propagating **tight** mask (un-dilated, so the
/// mask doesn't balloon — dilation is applied fresh each frame only for the fill). Serial (mapToVideo calls
/// `next` in order).
final class MaskPropagator {
    private let initialMask: CGImage
    private let provider: (any InpaintProvider)?
    private let quality: InpaintQuality
    private let dilation: Int
    private let flow: (@Sendable (CGImage, CGImage) async throws -> DenseFlow)?

    private var prevFrame: CGImage?
    private var prevTight: [Float]?          // propagating mask (binary 0/1), un-dilated, at frame res
    private var w = 0, h = 0

    init(initialMask: CGImage, provider: (any InpaintProvider)?, quality: InpaintQuality, dilation: Int,
         flow: (@Sendable (CGImage, CGImage) async throws -> DenseFlow)?) {
        self.initialMask = initialMask; self.provider = provider; self.quality = quality
        self.dilation = dilation; self.flow = flow
    }

    func next(_ frame: CGImage) async throws -> CGImage {
        let fw = frame.width, fh = frame.height
        var tight: [Float]
        if let pf = prevFrame, let pm = prevTight, fw == w, fh == h, let flow {
            let f = try await flow(frame, pf)                                   // cur→prev (for backward warp)
            let (warped, _) = FlowWarp.backwardWarp(prevMatte: pm, width: fw, height: fh, flow: f)
            tight = warped.map { $0 > 0.5 ? 1 : 0 }                             // keep binary
        } else {
            tight = Self.grayFloats(initialMask, fw, fh).map { $0 > 0.5 ? 1 : 0 }   // frame 0 (or no-flow): painted mask
        }
        prevTight = tight; prevFrame = frame; w = fw; h = fh

        var maskCG = Self.grayCGImage(tight, fw, fh)
        if dilation > 0 { maskCG = MaskOps.dilate(maskCG, radius: dilation) }
        return try await Eraser.erase(frame, mask: maskCG, provider: provider, quality: quality)  // mask already dilated
    }

    // MARK: - 1-channel gray ⇄ [Float] (0…1, row-major), mask resized to frame res

    static func grayFloats(_ image: CGImage, _ w: Int, _ h: Int) -> [Float] {
        var bytes = [UInt8](repeating: 0, count: w * h)
        if let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                               space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))         // auto-resizes a mismatched mask
        }
        return bytes.map { Float($0) / 255 }
    }
    static func grayCGImage(_ buf: [Float], _ w: Int, _ h: Int) -> CGImage {
        var bytes = buf.map { UInt8(max(0, min(255, ($0 * 255).rounded()))) }
        return CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            .makeImage()!
    }
}
