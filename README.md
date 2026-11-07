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

## EraseFill: the generative fill route (0.3.0)

`import EraseFill` gets `FillRoute`: the pixel steps of generative fill and extend, around an edit model that the
caller runs. The steps are:
- the magenta marker and its instruction text;
- the paint guard, which catches a kept marker or a dark extend;
- the seam harmonize;
- the composite through the mask, which leaves every unmasked pixel exact;
- the padded extend canvas and its per-side masks;
- the seam band.

These are the steps the Generative Fill bake-off measured (AB-R-0534), and this is the **one implementation**. Both
ForgeCore's `GenerativeFillRoute`, which ForgeCore re-exports, and pixel-agency-normalizer, which Gaea and Pixel Agency
Desktop use, call it (AB-A-0180). Any change here changes what was measured, so run ForgeCore's
`GenerativeFillLiveTests/bakeOffReproduces` after one.

It's a separate product with no dependencies, CoreGraphics only, so linking it doesn't pull media-bridge in.

## Install

```swift
.package(url: "https://github.com/xocialize/EraseKit.git", from: "0.3.0")
// .product(name: "EraseKit", package: "EraseKit")   — erase + the inpaint seam
// .product(name: "EraseFill", package: "EraseKit")  — the generative fill route only
```

EraseKit depends on [`media-bridge`](https://github.com/xocialize/media-bridge) only; EraseFill on nothing. MIT.
