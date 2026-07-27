# EraseKit

Object removal: paint over what you don't want, get it filled in.

```swift
import EraseKit

// Tier 0: classical fill, no model, no download.
let cleaned = try await Eraser.erase(image, mask: mask, provider: nil)

// Tier 2: same call, an inpainting model handles large or structured holes.
let cleaned = try await Eraser.erase(image, mask: mask, provider: myInpaintProvider, quality: .best)
```

The mask is grayscale, **white = remove, black = keep**, and may be a different size than the image (the
implementation resizes). It can come from anywhere — a brush, a selection, or a
[`MaskKit`](https://github.com/xocialize/MaskKit) prompt provider turning one click into a mask.

`ClassicalInpainter` (Tier 0) genuinely works for small holes, so erase is useful with no provider
injected; the engine tiers upgrade quality where classical fill visibly smears. `VideoEraser` handles
clips, with an optional flow provider for propagating a mask across frames.

## The seam

```swift
public protocol InpaintProvider: Sendable {
    var name: String { get }
    func inpaint(_ image: CGImage, mask: CGImage, quality: InpaintQuality) async throws -> CGImage
}
```

The one Forge seam taking two inputs — inpainting needs the hole alongside the picture.

EraseKit stays **net-clean**: no MLX, no weights, macOS 14 floor. MLX implementations (LaMa for structured
backgrounds, MI-GAN for speed) live in [`ForgeCore`](https://github.com/xocialize/ForgeCore).

## Install

```swift
.package(url: "https://github.com/xocialize/EraseKit.git", from: "0.1.0")
```

Depends on [`media-bridge`](https://github.com/xocialize/media-bridge) only. MIT.
