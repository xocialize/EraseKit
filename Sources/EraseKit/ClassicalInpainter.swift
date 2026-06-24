import CoreGraphics

/// **Tier-0 net-clean inpainter** — no weights, no engine. Fills the masked hole by **diffusion** (the
/// discrete Laplace equation: each hole pixel relaxes to the average of its neighbours, with the surrounding
/// known pixels as the boundary condition). Good for **small holes** — scratches, dust, blemishes, small
/// objects — where a smooth fill from the surround is plausible. Large object holes want a learned model
/// (LaMa/MI-GAN via `InpaintProvider`); diffusion smears those. Pure CoreGraphics + Swift; net-clean.
///
/// Cost is bounded to the hole's bounding box (× iterations), not the whole image, so it stays cheap on a 4K
/// frame with a small mask. Gauss-Seidel relaxation (in-place) for faster convergence than Jacobi.
public enum ClassicalInpainter {
    /// Fill `image`'s masked region. `mask` is grayscale, **white = hole/fill**; it's rendered to the image's
    /// resolution, so size needn't match. `iterations` defaults to a value scaled to the hole size (`nil`).
    public static func fill(_ image: CGImage, mask: CGImage, iterations: Int? = nil) -> CGImage {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return image }
        var rgb = rgbFloats(image, width: w, height: h)               // interleaved RGB, 0…1
        let m = grayFloats(mask, width: w, height: h)                 // mask rendered to image res

        var hole = [Bool](repeating: false, count: w * h)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where m[y * w + x] > 0.5 {
                hole[y * w + x] = true
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return image }                        // empty mask → no-op

        // Seed holes from the box mean so the relaxation starts neutral (faster than seeding 0/black).
        var seed: (Float, Float, Float) = (0, 0, 0); var known = 0
        for y in max(0, minY - 1)...min(h - 1, maxY + 1) {
            for x in max(0, minX - 1)...min(w - 1, maxX + 1) where !hole[y * w + x] {
                let i = (y * w + x) * 3; seed.0 += rgb[i]; seed.1 += rgb[i + 1]; seed.2 += rgb[i + 2]; known += 1
            }
        }
        if known > 0 { seed = (seed.0 / Float(known), seed.1 / Float(known), seed.2 / Float(known)) }
        for y in minY...maxY {
            for x in minX...maxX where hole[y * w + x] {
                let i = (y * w + x) * 3; rgb[i] = seed.0; rgb[i + 1] = seed.1; rgb[i + 2] = seed.2
            }
        }

        let iters = iterations ?? min(2 * max(maxX - minX, maxY - minY) + 24, 1500)
        for _ in 0..<iters {
            for y in minY...maxY {
                for x in minX...maxX {
                    let p = y * w + x
                    guard hole[p] else { continue }
                    let i = p * 3
                    for c in 0..<3 {
                        var sum: Float = 0, n: Float = 0
                        if x > 0 { sum += rgb[(p - 1) * 3 + c]; n += 1 }
                        if x < w - 1 { sum += rgb[(p + 1) * 3 + c]; n += 1 }
                        if y > 0 { sum += rgb[(p - w) * 3 + c]; n += 1 }
                        if y < h - 1 { sum += rgb[(p + w) * 3 + c]; n += 1 }
                        rgb[i + c] = n > 0 ? sum / n : rgb[i + c]
                    }
                }
            }
        }
        return rgbCGImage(rgb, width: w, height: h)
    }

    // MARK: - RGB / gray raster helpers (row-major, 0…1)

    static func rgbFloats(_ image: CGImage, width w: Int, height h: Int) -> [Float] {
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        if let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var out = [Float](repeating: 0, count: w * h * 3)
        for p in 0..<(w * h) {
            out[p * 3] = Float(bytes[p * 4]) / 255
            out[p * 3 + 1] = Float(bytes[p * 4 + 1]) / 255
            out[p * 3 + 2] = Float(bytes[p * 4 + 2]) / 255
        }
        return out
    }

    static func grayFloats(_ image: CGImage, width w: Int, height h: Int) -> [Float] {
        var bytes = [UInt8](repeating: 0, count: w * h)
        if let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                               space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return bytes.map { Float($0) / 255 }
    }

    static func rgbCGImage(_ buf: [Float], width w: Int, height h: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for p in 0..<(w * h) {
            bytes[p * 4] = UInt8(max(0, min(255, (buf[p * 3] * 255).rounded())))
            bytes[p * 4 + 1] = UInt8(max(0, min(255, (buf[p * 3 + 1] * 255).rounded())))
            bytes[p * 4 + 2] = UInt8(max(0, min(255, (buf[p * 3 + 2] * 255).rounded())))
        }
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
}
