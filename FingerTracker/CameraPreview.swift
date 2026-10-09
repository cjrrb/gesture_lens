//
//  CameraPreview.swift
//  FingerTracker
//

import AVFoundation
import AppKit
import CoreImage
import SwiftUI

/// Displays the live camera feed, unmirrored. Mirror it in SwiftUI with `scaleEffect(x: -1)`.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    /// Hue rotation in degrees (0 = unchanged).
    var hue: Double = 0
    /// Saturation multiplier (0 = grayscale, 1 = unchanged, 2 = double).
    var saturation: Double = 1

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        // SwiftUI sizes this view to the video's exact aspect ratio, so filling it never distorts.
        previewLayer.videoGravity = .resize
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        // Disable automatic mirroring so the feed always matches Vision's coordinates.
        if let connection = previewLayer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        view.layer = previewLayer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Core Image filters applied to the preview layer's contents.
        var filters: [CIFilter] = []
        if hue != 0, let hueFilter = CIFilter(name: "CIHueAdjust") {
            hueFilter.setValue(hue * .pi / 180, forKey: kCIInputAngleKey)
            filters.append(hueFilter)
        }
        if saturation != 1, let colorFilter = CIFilter(name: "CIColorControls") {
            colorFilter.setValue(saturation, forKey: kCIInputSaturationKey)
            filters.append(colorFilter)
        }
        nsView.contentFilters = filters
    }
}
