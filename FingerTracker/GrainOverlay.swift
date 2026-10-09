//
//  GrainOverlay.swift
//  FingerTracker
//

import SwiftUI

/// Animated film grain: a few random noise tiles cycled at ~24 fps.
struct GrainOverlay: View {
    /// 0 (no grain) … 1 (maximum grain).
    let intensity: Double
    /// When false, draws a single still grain frame (used when rendering photos).
    var animated = true

    private static let frameRate = 24.0
    private static let frames: [Image] = (0..<6).compactMap { _ in makeNoiseImage(size: 256) }

    var body: some View {
        if intensity > 0, !Self.frames.isEmpty {
            if animated {
                TimelineView(.periodic(from: .now, by: 1 / Self.frameRate)) { context in
                    let index = Int(context.date.timeIntervalSinceReferenceDate * Self.frameRate) % Self.frames.count
                    grain(Self.frames[index])
                }
            } else {
                grain(Self.frames[0])
            }
        }
    }

    private func grain(_ image: Image) -> some View {
        image
            .resizable(resizingMode: .tile)
            .opacity(intensity)
    }

    /// Builds a square tile of random light and dark specks with random transparency.
    private static func makeNoiseImage(size: Int) -> Image? {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let luminance = UInt8.random(in: 0...1) == 0 ? 0 : 255
            let alpha = UInt8.random(in: 0...160)
            // Premultiplied alpha: color channels are scaled by alpha.
            let channel = UInt8(Int(luminance) * Int(alpha) / 255)
            pixels[i] = channel
            pixels[i + 1] = channel
            pixels[i + 2] = channel
            pixels[i + 3] = alpha
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false,
                                    intent: .defaultIntent) else { return nil }
        // Scale > 1 packs more noise pixels into each point, making the specks finer.
        return Image(decorative: cgImage, scale: 1.5)
    }
}
