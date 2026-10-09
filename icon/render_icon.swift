//
//  render_icon.swift
//  gesture_lens
//
//  Draws the app icon in the app's terminal style and writes every size into AppIcon.appiconset.
//  Usage (from the project folder):
//    swiftc -module-cache-path /tmp/gl_modcache icon/render_icon.swift -o /tmp/render_icon && /tmp/render_icon
//

import AppKit
import SwiftUI

/// The icon is designed on a 1024-point canvas, following the macOS icon grid (an 824-point body).
let canvas: CGFloat = 1024
let bodySize: CGFloat = 824

func mono(_ size: CGFloat) -> Font {
    .system(size: size, weight: .thin, design: .monospaced)
}

/// Same look as the app's film grain.
func noiseImage(size: Int) -> Image {
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let luminance = UInt8.random(in: 0...1) == 0 ? 0 : 255
        let alpha = UInt8.random(in: 0...160)
        let channel = UInt8(Int(luminance) * Int(alpha) / 255)
        pixels[i] = channel
        pixels[i + 1] = channel
        pixels[i + 2] = channel
        pixels[i + 3] = alpha
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let cgImage = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                          bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return Image(decorative: cgImage, scale: 1)
}

/// Four corner brackets framing the center, like a camera viewfinder.
struct Viewfinder: Shape {
    let inset: CGFloat
    let arm: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                 (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        }
        return path
    }
}

struct Icon: View {
    /// Final pixel size; lines get relatively thicker as the icon shrinks so they never vanish.
    let pixels: CGFloat

    /// A line width in canvas points that is never thinner than `minPixels` in the final image.
    func line(_ width: CGFloat, minPixels: CGFloat = 1.2) -> CGFloat {
        max(width, minPixels * canvas / pixels)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 185, style: .continuous)
        // In the body's coordinates, since everything below is laid out inside the body frame.
        let center = CGPoint(x: bodySize / 2, y: bodySize / 2)
        ZStack {
            shape.fill(.black)
            if pixels >= 64 {
                noiseImage(size: 256)
                    .resizable(resizingMode: .tile)
                    .opacity(0.08)
                    .clipShape(shape)
            }
            // A faint edge so the icon doesn't disappear against dark backgrounds.
            shape.stroke(.white.opacity(0.18), lineWidth: line(3, minPixels: 0.5))

            Viewfinder(inset: 150, arm: 96)
                .stroke(.white, style: StrokeStyle(lineWidth: line(10), lineCap: .square))
                .frame(width: bodySize, height: bodySize)

            // Fingertip marker from the hand skeleton: a thin ring around a small dot.
            Circle()
                .stroke(.white, lineWidth: line(10))
                .frame(width: 240, height: 240)
            Circle()
                .fill(.white)
                .frame(width: max(32, 3 * canvas / pixels), height: max(32, 3 * canvas / pixels))

            // Coordinate readout, as shown above every tracked fingertip (too small to read below 128 px).
            if pixels >= 128 {
                Text("0.50 0.50")
                    .font(mono(52))
                    .foregroundStyle(.white.opacity(0.7))
                    .position(x: center.x, y: center.y - 120 - 56)
            }
        }
        .frame(width: bodySize, height: bodySize)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
        .frame(width: canvas, height: canvas)
    }
}

@MainActor
func render(pixels: Int, to url: URL) {
    let renderer = ImageRenderer(content: Icon(pixels: CGFloat(pixels)))
    renderer.scale = CGFloat(pixels) / canvas
    guard let cgImage = renderer.cgImage,
          let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
        fatalError("Couldn't render \(url.lastPathComponent)")
    }
    try! data.write(to: url)
}

let iconSet = URL(filePath: "gesture_lens/Assets.xcassets/AppIcon.appiconset", directoryHint: .isDirectory)
var images: [[String: String]] = []
MainActor.assumeIsolated {
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
            render(pixels: size * scale, to: iconSet.appending(path: name))
            images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
        }
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: iconSet.appending(path: "Contents.json"))
