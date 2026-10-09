//
//  PhotoRenderer.swift
//  gesture_lens
//

import CoreImage
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The look applied to the live preview, captured at the moment a photo is taken.
struct PhotoSettings {
    var brightness: Double
    var grain: Double
    var hue: Double
    var saturation: Double
    var vignetteColor: Color?
    /// Hands to draw as skeletons (empty when the skeleton is turned off).
    var hands: [TrackedHand] = []
    /// Faces to draw boxes around (empty when the face tracker is turned off).
    var faces: [TrackedFace] = []
    /// Width of the video on screen, so tracking overlays can be scaled to look the same in the photo.
    var onScreenVideoWidth: CGFloat = 0
}

/// Turns a camera frame into a photo with the same effects as the live preview, and saves it to ~/Pictures/snap_shots.
enum PhotoRenderer {
    private static let ciContext = CIContext()

    /// Renders a mirrored photo of `pixelBuffer` with every effect applied, plus any tracking overlays in
    /// `settings` (but never the on-screen controls).
    static func render(_ pixelBuffer: CVPixelBuffer, settings: PhotoSettings) -> CGImage? {
        // Mirror to match the preview, then apply the same Core Image color filters as the live view.
        var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.upMirrored)
        if settings.hue != 0, let hueFilter = CIFilter(name: "CIHueAdjust") {
            hueFilter.setValue(image, forKey: kCIInputImageKey)
            hueFilter.setValue(settings.hue * .pi / 180, forKey: kCIInputAngleKey)
            image = hueFilter.outputImage ?? image
        }
        if settings.saturation != 1, let colorFilter = CIFilter(name: "CIColorControls") {
            colorFilter.setValue(image, forKey: kCIInputImageKey)
            colorFilter.setValue(settings.saturation, forKey: kCIInputSaturationKey)
            image = colorFilter.outputImage ?? image
        }
        guard let filtered = ciContext.createCGImage(image, from: image.extent) else { return nil }

        // Composite the SwiftUI-drawn effects (tint, vignette, grain) exactly as the live view draws them.
        let size = CGSize(width: filtered.width, height: filtered.height)
        let brightness = settings.brightness
        let content = ZStack {
            Image(decorative: filtered, scale: 1)
            Rectangle()
                .fill(brightness >= 0 ? Color.white.opacity(brightness * 0.6) : Color.black.opacity(-brightness * 0.85))
            if let vignetteColor = settings.vignetteColor {
                EllipticalGradient(colors: [.clear, vignetteColor.opacity(0.8)], center: .center,
                                   startRadiusFraction: 0.3, endRadiusFraction: 0.75)
            }
            GrainOverlay(intensity: settings.grain * 0.4, animated: false)
            // Lines and text are sized in on-screen points, so scale them up to the photo's resolution.
            TrackingOverlay(hands: settings.hands, faces: settings.faces,
                            showsSkeleton: !settings.hands.isEmpty, showsFaces: !settings.faces.isEmpty,
                            rect: CGRect(origin: .zero, size: size),
                            scale: settings.onScreenVideoWidth > 0 ? size.width / settings.onScreenVideoWidth : 1)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return renderer.cgImage
    }

    /// Name of the folder inside ~/Pictures that photos are saved to.
    static let folderName = "snap_shots"

    /// Saves `image` as a JPEG in ~/Pictures/snap_shots (creating the folder if needed) and returns the file's URL.
    static func saveToPictures(_ image: CGImage) throws -> URL {
        let folder = picturesDirectory().appending(path: folderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = folder.appending(path: "gesture_lens \(formatter.string(from: .now)).jpg")

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        return url
    }

    /// The real ~/Pictures (the sandbox grants read/write access to it). In a sandboxed app the home directory
    /// APIs point inside the app's container, so look up the user's actual home directory instead.
    private static func picturesDirectory() -> URL {
        if let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir {
            return URL(filePath: String(cString: home), directoryHint: .isDirectory).appending(path: "Pictures")
        }
        return URL.picturesDirectory
    }
}
