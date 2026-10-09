//
//  CameraPreview.swift
//  FingerTracker
//

import AVFoundation
import AppKit
import SwiftUI

/// Displays the live camera feed, unmirrored. Mirror it in SwiftUI with `scaleEffect(x: -1)`.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

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

    func updateNSView(_ nsView: NSView, context: Context) {}
}
