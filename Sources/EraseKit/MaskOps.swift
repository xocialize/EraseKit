import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Net-clean mask morphology. Inpainters want the removal mask to **fully cover the subject + a small margin**
/// — a tight mask leaves an edge halo of the original object (part of the "melted" look). `dilate` grows the
/// white (remove) region by `radius` px via CoreImage's morphology max. CoreImage = net-clean (Apple, no MLX).
public enum MaskOps {
    /// Color-management OFF: a mask is coverage, not colour — managed working spaces gamma-shift the grayscale.
    static let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    /// Grow the white region of a grayscale mask by `radius` px (morphological dilation). `radius <= 0` → unchanged.
    public static func dilate(_ mask: CGImage, radius: Int) -> CGImage {
        guard radius > 0 else { return mask }
        let ci = CIImage(cgImage: mask)
        let f = CIFilter.morphologyMaximum()
        f.inputImage = ci
        f.radius = Float(radius)
        guard let out = f.outputImage,
              let cg = ciContext.createCGImage(out.cropped(to: ci.extent), from: ci.extent) else { return mask }
        return cg
    }
}
