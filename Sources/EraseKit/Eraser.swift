import CoreGraphics

public enum EraseError: Error, CustomStringConvertible {
    case emptyMask
    case renderFailed
    public var description: String {
        switch self {
        case .emptyMask: return "the erase mask is empty (nothing selected to remove)"
        case .renderFailed: return "failed to load / render the erased image"
        }
    }
}

/// Net-clean entry point: erase (object-remove / inpaint) the masked region of `image`. With an injected
/// `InpaintProvider` → the engine fills (LaMa quality / MI-GAN fast); **without** one → the net-clean Tier-0
/// `ClassicalInpainter` (diffusion) fills, so Erase works with no model for small holes (scratches/dust).
/// `mask`: grayscale, white = remove. `maskDilation` grows the mask by N px first so the fill fully covers the
/// subject + a margin (no edge halo) — recommended for object removal.
public enum Eraser {
    public static func erase(_ image: CGImage, mask: CGImage, provider: (any InpaintProvider)?,
                             quality: InpaintQuality = .best, maskDilation: Int = 0) async throws -> CGImage {
        let m = maskDilation > 0 ? MaskOps.dilate(mask, radius: maskDilation) : mask
        if let provider { return try await provider.inpaint(image, mask: m, quality: quality) }
        return ClassicalInpainter.fill(image, mask: m)
    }
}
