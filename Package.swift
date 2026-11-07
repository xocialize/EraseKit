// swift-tools-version: 6.2
import PackageDescription

// EraseKit — the **Erase** (object removal / inpainting) capability's pure plugin. Object removal = *mask the
// thing* + *fill the hole*. The mask comes from the inspector (brush/box, later EdgeTAM); EraseKit owns the
// FILL: a net-clean **Tier-0 classical** inpainter (diffusion, no weights — good for scratches/dust/small
// holes) + the **two-input `InpaintProvider` seam** (image + mask) for the engine tiers (MI-GAN fast / LaMa
// quality), injected at the app layer (keeps EraseKit/EraseUI MLX-free). See ../../ERASE-PLAN.md.
//
// **EraseFill** (0.3.0, AB-A-0180) holds the generative fill route's pixel steps (`FillRoute`: the marker, the paint
// guard, harmonize, composite, the extend canvas, the seam band). It is the one implementation that ForgeCore and
// pixel-agency-normalizer both call. It is its own product with NO dependencies, CoreGraphics only, so the
// MLX-free normalizer links it without pulling media-bridge into its graph.
let package = Package(
    name: "EraseKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EraseKit", targets: ["EraseKit"]),
        .library(name: "EraseFill", targets: ["EraseFill"]),
    ],
    dependencies: [
        // media-bridge's MediaMeasure owns the net-clean video frame map + the FlowWarp/DenseFlow substrate
        // reused for video erase (flow-propagate the painted mask so it tracks a moving subject). Net-clean.
        .package(url: "https://github.com/xocialize/media-bridge.git", from: "0.2.0"),
    ],
    targets: [
        .target(name: "EraseKit",
                dependencies: [.product(name: "MediaMeasure", package: "media-bridge")]),
        .target(name: "EraseFill"),
        .testTarget(name: "EraseKitTests",
                    dependencies: ["EraseKit", .product(name: "MediaMeasure", package: "media-bridge")]),
        .testTarget(name: "EraseFillTests", dependencies: ["EraseFill"]),
    ]
)
