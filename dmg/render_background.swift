//
//  render_background.swift
//  gesture_lens
//
//  Draws the DMG window background in the app's terminal style.
//  Usage: swift render_background.swift <output folder>
//  Writes background.png (1x) and background@2x.png into the folder.
//

import AppKit
import SwiftUI

/// Window size in points; must match the bounds set in make_dmg.sh.
let windowSize = CGSize(width: 640, height: 400)
/// Icon centers in points; must match the icon positions set in make_dmg.sh.
let appCenter = CGPoint(x: 170, y: 190)
let applicationsCenter = CGPoint(x: 470, y: 190)
/// Half the side of the tracking box drawn around each icon.
let boxRadius: CGFloat = 72

func mono(_ size: CGFloat) -> Font {
    .system(size: size, weight: .thin, design: .monospaced)
}

/// Same look as the app's film grain: random light and dark specks with random transparency.
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
    return Image(decorative: cgImage, scale: 1.5)
}

/// A face-tracking-style box around an icon, with a coordinate label above it.
struct TrackingBox: View {
    let center: CGPoint

    var body: some View {
        Rectangle()
            .stroke(.white, lineWidth: 0.75)
            .frame(width: boxRadius * 2, height: boxRadius * 2)
            .position(center)
        Text(String(format: "%.2f %.2f", center.x / windowSize.width, center.y / windowSize.height))
            .font(mono(10))
            .opacity(0.7)
            .position(x: center.x, y: center.y - boxRadius - 10)
    }
}

/// A mid-gray chip under each icon so Finder's label stays readable in both Light and Dark Mode
/// (Finder draws labels black in Light Mode and white in Dark Mode, and can't be told otherwise).
struct LabelChip: View {
    let center: CGPoint

    var body: some View {
        Rectangle()
            .fill(Color(white: 0.55))
            .overlay(Rectangle().stroke(.white, lineWidth: 0.75))
            .frame(width: 128, height: 20)
            .position(x: center.x, y: center.y + boxRadius - 12)
    }
}

/// The drag arrow, drawn like the app's horizontal slider with a fingertip "grabbing" its thumb.
struct DragTrack: View {
    var body: some View {
        let y = appCenter.y
        let start = appCenter.x + boxRadius + 16
        let end = applicationsCenter.x - boxRadius - 16
        let thumbX = start + (end - start) * 0.35

        Path { path in
            path.move(to: CGPoint(x: start, y: y))
            path.addLine(to: CGPoint(x: end, y: y))
            for x in [start, (start + end) / 2] {
                path.move(to: CGPoint(x: x, y: y - 5))
                path.addLine(to: CGPoint(x: x, y: y + 5))
            }
            // Arrowhead in place of the right-hand tick.
            path.move(to: CGPoint(x: end - 7, y: y - 6))
            path.addLine(to: CGPoint(x: end, y: y))
            path.addLine(to: CGPoint(x: end - 7, y: y + 6))
        }
        .stroke(.white.opacity(0.6), lineWidth: 0.75)

        // Filled thumb (the "active" state) under a fingertip ring, as in the hand skeleton.
        Circle()
            .fill(.white.opacity(0.8))
            .frame(width: 12, height: 12)
            .position(x: thumbX, y: y)
        Circle()
            .stroke(.white, lineWidth: 0.75)
            .frame(width: 18, height: 18)
            .position(x: thumbX, y: y)
        Text(String(format: "%.2f %.2f", thumbX / windowSize.width, y / windowSize.height))
            .font(mono(10))
            .opacity(0.7)
            .position(x: thumbX, y: y - 20)

        Text("drag")
            .font(mono(10))
            .position(x: (start + end) / 2, y: y + 18)
    }
}

struct Background: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            noiseImage(size: 256)
                .resizable(resizingMode: .tile)
                .opacity(0.1)

            VStack(alignment: .leading, spacing: 6) {
                Text("gesture_lens")
                Text(String(repeating: "─", count: 28))
                    .opacity(0.4)
                Text("> install_")
                    .opacity(0.6)
            }
            .font(mono(12))
            .padding(.leading, 24)
            .padding(.top, 20)

            TrackingBox(center: appCenter)
            TrackingBox(center: applicationsCenter)
            LabelChip(center: appCenter)
            LabelChip(center: applicationsCenter)
            DragTrack()

            VStack(alignment: .leading, spacing: 6) {
                Text("> drag gesture_lens into applications")
                Text("> first launch: open it, then system settings › privacy & security › open anyway")
                    .opacity(0.6)
            }
            .font(mono(10))
            .padding(.leading, 24)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 24)
        }
        .foregroundStyle(.white)
        .frame(width: windowSize.width, height: windowSize.height)
    }
}

@MainActor
func write(scale: CGFloat, to url: URL) {
    let renderer = ImageRenderer(content: Background())
    renderer.scale = scale
    guard let cgImage = renderer.cgImage,
          let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
        fatalError("Couldn't render \(url.lastPathComponent)")
    }
    try! data.write(to: url)
}

let folder = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".", directoryHint: .isDirectory)
MainActor.assumeIsolated {
    write(scale: 1, to: folder.appending(path: "background.png"))
    write(scale: 2, to: folder.appending(path: "background@2x.png"))
}
