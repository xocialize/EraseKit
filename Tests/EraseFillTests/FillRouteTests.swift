//
//  FillRouteTests.swift
//  EraseFillTests
//
//  The route's pixel steps on small fixtures, no GPU. The orchestration (guard retries, windowing, LaMa bridging)
//  is tested where it lives, ForgeCore's GenerativeFillRouteTests; the bake-off's pixel-for-pixel check is
//  ForgeCore's GenerativeFillLiveTests/bakeOffReproduces.
//

import CoreGraphics
import Testing
@testable import EraseFill

@Suite struct FillRouteTests {

    static func gradient(_ w: Int, _ h: Int) -> FillPixels {
        var p = FillPixels(width: w, height: h)
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4
            p.rgba[i] = UInt8(x * 255 / max(1, w - 1)); p.rgba[i + 1] = UInt8(y * 255 / max(1, h - 1)); p.rgba[i + 2] = 90; p.rgba[i + 3] = 255
        } }
        return p
    }

    static func box(_ w: Int, _ h: Int, _ b: FillBox, value: UInt8 = 255) -> FillMask {
        var m = FillMask(width: w, height: h)
        for y in b.y..<(b.y + b.height) { for x in b.x..<(b.x + b.width) { m.values[y * w + x] = value } }
        return m
    }

    @Test func theInstructionsAndMarkerAreTheBakeOffsVerbatim() {
        #expect(FillRoute.marker == [255, 0, 255, 255])
        #expect(FillRoute.fillInstruction(prompt: "") ==
            "Fill the bright magenta area so it blends seamlessly into the rest of the picture, as if nothing had been there. Keep everything else unchanged.")
        #expect(FillRoute.extendInstruction(left: 64, top: 0, right: 64, bottom: 0, prompt: "") ==
            "Replace the bright magenta areas at the left and right edges with a seamless continuation of the scene. Keep everything else unchanged.")
        #expect(!FillRoute.checkable(prompt: "a Pink flamingo"))
        #expect(FillRoute.checkable(prompt: "a red car"))
    }

    @Test func markPaintsOnlyTheRegionAndTheGuardSeesIt() {
        let img = Self.gradient(32, 24), region = Self.box(32, 24, FillBox(x: 8, y: 6, width: 10, height: 8))
        let marked = FillRoute.mark(img, region: region)
        for i in 0..<(32 * 24) {
            let px = Array(marked.rgba[i * 4..<i * 4 + 4])
            if region.values[i] > 0 { #expect(px == FillRoute.marker) } else { #expect(px == Array(img.rgba[i * 4..<i * 4 + 4])) }
        }
        #expect(FillRoute.paintingProblem(marked, canvas: img, parts: [region], checkDark: false) == "marker")
        #expect(FillRoute.paintingProblem(img, canvas: img, parts: [region], checkDark: true) == nil)
    }

    @Test func compositeLeavesUnmaskedPixelsExactAndBlendsGrey() {
        let original = Self.gradient(16, 16)
        var result = FillPixels(width: 16, height: 16, rgba: [UInt8](repeating: 200, count: 16 * 16 * 4))
        for i in 0..<(16 * 16) { result.rgba[i * 4 + 3] = 255 }
        var mask = Self.box(16, 16, FillBox(x: 4, y: 4, width: 4, height: 4))
        mask.values[0] = 128
        let out = FillRoute.composite(result: result, over: original, mask: mask)
        for i in 1..<(16 * 16) where mask.values[i] == 0 { #expect(out.rgba[i * 4..<i * 4 + 4] == original.rgba[i * 4..<i * 4 + 4]) }
        #expect(out.rgba[(4 * 16 + 4) * 4] == 200)
        #expect(out.rgba[0] == UInt8((200 * 128 + Int(original.rgba[0]) * 127 + 127) / 255))
    }

    @Test func padKeepsTheOriginalAndMasksExactlyTheNewSides() {
        let img = Self.gradient(20, 10)
        let (canvas, mask) = FillRoute.pad(img, left: 3, top: 2, right: 5, bottom: 0)
        #expect(canvas.width == 28 && canvas.height == 12)
        #expect(mask.values.filter { $0 > 0 }.count == 28 * 12 - 20 * 10)
        #expect(FillRoute.crop(canvas, FillBox(x: 3, y: 2, width: 20, height: 10)) == img)
        let sides = FillRoute.sides(width: 28, height: 12, left: 3, top: 2, right: 5, bottom: 0)
        #expect(sides.count == 3)
        var union = [UInt8](repeating: 0, count: 28 * 12)
        for s in sides { for i in union.indices where s.values[i] > 0 { #expect(union[i] == 0); union[i] = 255 } }
        #expect(union == mask.values)
    }

    @Test func harmonizeChangesNothingWhenTheResultAlreadyMatches() {
        let img = Self.gradient(40, 30), region = Self.box(40, 30, FillBox(x: 10, y: 10, width: 12, height: 8))
        #expect(FillRoute.harmonize(img, toward: img, region: region) == img)
    }

    @Test func harmonizeCarriesAToneShiftIntoTheRegion() {
        let original = Self.gradient(40, 30), region = Self.box(40, 30, FillBox(x: 14, y: 10, width: 12, height: 10))
        var drifted = original
        for i in 0..<(40 * 30) { for c in 0..<3 { drifted.rgba[i * 4 + c] = UInt8(max(0, Int(original.rgba[i * 4 + c]) - 10)) } }
        let out = FillRoute.harmonize(drifted, toward: original, region: region)
        // On the flat channel (blue 90, drifted to 80): at the seam, the region's first column, most of the drift is
        // undone (measured 88). The correction fades with distance by design (the half-cell floor), so six pixels in it
        // is gone (80). It never overshoots the original anywhere.
        let seam = (15 * 40 + 14) * 4, centre = (15 * 40 + 20) * 4
        #expect(out.rgba[seam + 2] >= 87 && out.rgba[seam + 2] <= 90)
        for x in 14..<26 {
            let v = out.rgba[(15 * 40 + x) * 4 + 2]
            #expect(v >= 80 && v <= 90, "x=\(x)")
        }
        #expect(out.rgba[centre + 2] < out.rgba[seam + 2])
    }

    @Test func theSeamBandIsTheRegionsEdgeStrip() {
        let region = Self.box(30, 30, FillBox(x: 5, y: 5, width: 20, height: 20))
        let band = FillRoute.seamBand(of: region, width: 3)
        for y in 0..<30 { for x in 0..<30 {
            let inRegion = region.values[y * 30 + x] > 0
            let edge = inRegion && (x < 8 || x >= 22 || y < 8 || y >= 22)
            #expect((band.values[y * 30 + x] > 0) == edge, "(\(x),\(y))")
        } }
        #expect(FillRoute.seamBandWidth(width: 1920, height: 1080) == 40)
    }

    @Test func geometryRoundTrips() {
        let img = Self.gradient(24, 18), b = FillBox(x: 5, y: 3, width: 7, height: 9)
        #expect(FillRoute.bounds(of: Self.box(24, 18, b)) == b)
        #expect(FillRoute.bounds(of: FillMask(width: 4, height: 4)) == nil)
        #expect(FillRoute.paste(FillRoute.crop(img, b), into: img, at: b) == img)
        #expect(b.grown(by: 10, within: 24, 18) == FillBox(x: 0, y: 0, width: 22, height: 18))
    }

    @Test func theEnvelopeFitsThenClamps() {
        #expect(FillRoute.fit(width: 1030, height: 770, maxPixels: 2048 * 2048, multipleOf: 32)! == (1024, 768))
        #expect(FillRoute.fit(width: 4096, height: 4096, maxPixels: 2048 * 2048, multipleOf: 32) == nil)
        let c = FillRoute.clamp(width: 4000, height: 3000, maxPixels: 1024 * 1024, multipleOf: 32)
        #expect(c.width * c.height <= 1024 * 1024 && c.width % 32 == 0 && c.height % 32 == 0)
    }
}
