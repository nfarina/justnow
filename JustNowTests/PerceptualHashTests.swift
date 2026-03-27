import CoreGraphics
import XCTest
@testable import JustNow

final class PerceptualHashTests: XCTestCase {

    // MARK: - Helpers

    /// Create a solid-colour CGImage for testing.
    private func makeSolidImage(width: Int = 64, height: Int = 64, gray: UInt8) -> CGImage {
        var pixels = [UInt8](repeating: gray, count: width * height)
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        return context.makeImage()!
    }

    /// Create a checkerboard CGImage (alternating black/white 1-pixel cells).
    private func makeCheckerboardImage(width: Int = 64, height: Int = 64) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = ((x + y) % 2 == 0) ? 255 : 0
            }
        }
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        return context.makeImage()!
    }

    // MARK: - Hamming distance

    func testHammingDistanceOfIdenticalHashesIsZero() {
        XCTAssertEqual(PerceptualHash.hammingDistance(0xDEADBEEF, 0xDEADBEEF), 0)
    }

    func testHammingDistanceOfOppositeHashesIs64() {
        XCTAssertEqual(PerceptualHash.hammingDistance(0, UInt64.max), 64)
    }

    func testHammingDistanceIsSymmetric() {
        let a: UInt64 = 0xFF00FF00
        let b: UInt64 = 0x00FF00FF
        XCTAssertEqual(PerceptualHash.hammingDistance(a, b), PerceptualHash.hammingDistance(b, a))
    }

    func testHammingDistanceOfSingleBitDifferenceIsOne() {
        XCTAssertEqual(PerceptualHash.hammingDistance(0, 1), 1)
        XCTAssertEqual(PerceptualHash.hammingDistance(0, 1 << 63), 1)
    }

    // MARK: - Compute

    func testSameImageProducesSameHash() async {
        let image = makeSolidImage(gray: 128)
        let hash1 = await PerceptualHash.compute(from: image)
        let hash2 = await PerceptualHash.compute(from: image)
        XCTAssertEqual(hash1, hash2)
    }

    func testVisuallyDifferentImagesProduceDifferentHashes() async {
        let black = makeSolidImage(gray: 0)
        let checker = makeCheckerboardImage()

        let hashBlack = await PerceptualHash.compute(from: black)
        let hashChecker = await PerceptualHash.compute(from: checker)

        let distance = PerceptualHash.hammingDistance(hashBlack, hashChecker)
        XCTAssertGreaterThan(distance, 0, "Visually different images should have different hashes")
    }

    func testSimilarBrightnessImageHashesSimilar() async {
        let gray127 = makeSolidImage(gray: 127)
        let gray129 = makeSolidImage(gray: 129)

        let hash1 = await PerceptualHash.compute(from: gray127)
        let hash2 = await PerceptualHash.compute(from: gray129)

        let distance = PerceptualHash.hammingDistance(hash1, hash2)
        // Solid images of very similar brightness should hash identically or near-identically
        XCTAssertLessThanOrEqual(distance, 5, "Similar brightness solids should hash similarly")
    }
}
