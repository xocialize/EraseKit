import CoreGraphics

/// Quality tier for an engine inpaint. Mirrors the `MLXInpaint` package modes — `fast` = MI-GAN
/// (mobile/on-device), `best` = LaMa (FFC, large masks + structured backgrounds). Kept here so the capability,
/// inspector, and engine adapter share one vocabulary (the BiRefNet/DDColor fast/best precedent).
public enum InpaintQuality: String, Sendable, CaseIterable, Identifiable {
    case fast, best
    public var id: String { rawValue }
    public var displayName: String { self == .fast ? "Fast" : "Quality" }
}

/// The **Erase engine seam** — a *two-input* provider `(image, mask) → filled image`, the one place a Forge
/// capability seam takes more than a single image (inpainting needs the hole alongside the picture). The mask
/// is a grayscale `CGImage`, **white (high) = remove / fill, black = keep**; it may be at a different size than
/// the image (the implementation resizes). The net-clean Kit defines this contract; the engine-backed
/// implementation (LaMa / MI-GAN via `MLXServeEngine`) injects at the app layer, keeping EraseKit MLX-free.
///
/// Unlike Colorize there IS a usable no-engine path — `ClassicalInpainter` (Tier-0) — so the capability still
/// erases small holes with no provider injected; the engine tiers upgrade quality on large/structured holes.
/// `name` labels the inspector + tags the recorded artifact.
public protocol InpaintProvider: Sendable {
    var name: String { get }
    func inpaint(_ image: CGImage, mask: CGImage, quality: InpaintQuality) async throws -> CGImage
}
