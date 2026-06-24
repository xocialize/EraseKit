// swift-tools-version: 6.2
import PackageDescription

// EraseKit — the **Erase** (object removal / inpainting) capability's pure plugin. Object removal = *mask the
// thing* + *fill the hole*. The mask comes from the inspector (brush/box, later EdgeTAM); EraseKit owns the
// FILL: a net-clean **Tier-0 classical** inpainter (diffusion, no weights — good for scratches/dust/small
// holes) + the **two-input `InpaintProvider` seam** (image + mask) for the engine tiers (MI-GAN fast / LaMa
// quality), injected at the app layer (keeps EraseKit/EraseUI MLX-free). See ../../ERASE-PLAN.md.
let package = Package(
    name: "EraseKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EraseKit", targets: ["EraseKit"]),
    ],
    targets: [
        .target(name: "EraseKit"),
        .testTarget(name: "EraseKitTests", dependencies: ["EraseKit"]),
    ]
)
