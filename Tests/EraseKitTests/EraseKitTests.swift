import XCTest
import CoreGraphics
@testable import EraseKit

final class EraseKitTests: XCTestCase {
    private func solid(_ r: Float, _ g: Float, _ b: Float, _ w: Int, _ h: Int) -> CGImage {
        var arr = [Float](repeating: 0, count: w * h * 3)
        for p in 0..<(w * h) { arr[p * 3] = r; arr[p * 3 + 1] = g; arr[p * 3 + 2] = b }
        return ClassicalInpainter.rgbCGImage(arr, width: w, height: h)
    }
    private func maskRect(_ rx: Int, _ ry: Int, _ rw: Int, _ rh: Int, _ w: Int, _ h: Int) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: w * h)
        for y in ry..<(ry + rh) { for x in rx..<(rx + rw) { bytes[y * w + x] = 255 } }
        return CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            .makeImage()!
    }
    private struct StubInpainter: InpaintProvider {
        let name = "stub-engine"
        func inpaint(_ image: CGImage, mask: CGImage, quality: InpaintQuality) async throws -> CGImage {
            var arr = [Float](repeating: 0, count: image.width * image.height * 3)
            for p in 0..<(image.width * image.height) { arr[p * 3 + 2] = 1.0 }   // flat blue
            return ClassicalInpainter.rgbCGImage(arr, width: image.width, height: image.height)
        }
    }

    /// Diffusion fills a hole in a constant field to the surrounding colour (Laplace → constant).
    func testDiffusionFillsHoleToSurroundColour() {
        let w = 24, h = 24
        let out = ClassicalInpainter.fill(solid(0.78, 0.16, 0.16, w, h), mask: maskRect(8, 8, 8, 8, w, h))
        let rgb = ClassicalInpainter.rgbFloats(out, width: w, height: h)
        let i = (12 * w + 12) * 3                                   // a centre hole pixel
        XCTAssertEqual(rgb[i], 0.78, accuracy: 0.05, "hole filled to surround red")
        XCTAssertEqual(rgb[i + 1], 0.16, accuracy: 0.05)
        XCTAssertEqual(rgb[i + 2], 0.16, accuracy: 0.05)
    }

    /// Pixels outside the mask are untouched.
    func testKnownPixelsUnchanged() {
        let w = 16, h = 16
        let out = ClassicalInpainter.fill(solid(0.5, 0.5, 0.5, w, h), mask: maskRect(6, 6, 4, 4, w, h))
        let rgb = ClassicalInpainter.rgbFloats(out, width: w, height: h)
        let i = (1 * w + 1) * 3                                     // a corner, far from the hole
        XCTAssertEqual(rgb[i], 0.5, accuracy: 0.01)
    }

    /// Empty mask → no-op (returns the source unchanged).
    func testEmptyMaskIsNoOp() {
        let w = 8, h = 8
        let src = solid(0.3, 0.6, 0.9, w, h)
        let out = ClassicalInpainter.fill(src, mask: maskRect(0, 0, 0, 0, w, h))   // all-black mask
        let a = ClassicalInpainter.rgbFloats(src, width: w, height: h)
        let b = ClassicalInpainter.rgbFloats(out, width: w, height: h)
        for i in 0..<a.count { XCTAssertEqual(a[i], b[i], accuracy: 0.004) }
    }

    private func grayByte(_ cg: CGImage, _ x: Int, _ y: Int) -> UInt8 {
        let w = cg.width, h = cg.height
        var b = [UInt8](repeating: 0, count: w * h)
        CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            .draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return b[y * w + x]
    }

    /// Dilation grows the white (remove) region so the fill covers the subject + a margin.
    func testDilateGrowsMask() {
        let w = 24, h = 24
        let mask = maskRect(10, 10, 4, 4, w, h)               // 4×4 white square at (10,10)
        XCTAssertLessThan(grayByte(mask, 7, 12), 40, "before: 3px left of the square is black")
        let grown = MaskOps.dilate(mask, radius: 3)
        XCTAssertGreaterThan(grayByte(grown, 7, 12), 200, "after dilate(3): that pixel is now white")
        XCTAssertLessThan(grayByte(grown, 0, 0), 40, "a far corner stays black")
        // radius 0 = identity
        XCTAssertEqual(grayByte(MaskOps.dilate(mask, radius: 0), 12, 12), grayByte(mask, 12, 12))
    }

    /// Eraser routes through an injected provider when present...
    func testEraserUsesProvider() async throws {
        let w = 8, h = 8
        let out = try await Eraser.erase(solid(1, 0, 0, w, h), mask: maskRect(2, 2, 4, 4, w, h),
                                         provider: StubInpainter(), quality: .best)
        let rgb = ClassicalInpainter.rgbFloats(out, width: w, height: h)
        XCTAssertEqual(rgb[2], 1.0, accuracy: 0.02, "provider output (blue) used")   // B channel
    }

    /// ...and falls back to Tier-0 classical fill when no provider is injected (no engine required).
    func testEraserClassicalFallback() async throws {
        let w = 24, h = 24
        let out = try await Eraser.erase(solid(0.2, 0.7, 0.2, w, h), mask: maskRect(9, 9, 6, 6, w, h),
                                         provider: nil)
        let rgb = ClassicalInpainter.rgbFloats(out, width: w, height: h)
        let i = (12 * w + 12) * 3
        XCTAssertEqual(rgb[i + 1], 0.7, accuracy: 0.05, "classical fill used the surround green")
    }
}
