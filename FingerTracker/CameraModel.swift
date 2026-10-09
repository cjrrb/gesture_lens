//
//  CameraModel.swift
//  FingerTracker
//

import AVFoundation
import Observation
import Vision

/// A single detected fingertip.
struct FingerTip: Identifiable {
    let id: String
    let name: String
    /// Normalized position (0–1) with a top-left origin, already mirrored to match the preview.
    let location: CGPoint
}

/// A detected hand and its joints.
struct TrackedHand: Identifiable {
    let id: Int
    /// Normalized positions of every confidently detected joint, keyed by joint name (e.g. "indexPIP").
    let joints: [String: CGPoint]

    private static let tips: [(joint: String, name: String)] = [
        ("thumbTip", "Thumb"), ("indexTip", "Index"), ("middleTip", "Middle"), ("ringTip", "Ring"), ("littleTip", "Little")
    ]

    /// The detected fingertips, in thumb → little order.
    var fingers: [FingerTip] {
        Self.tips.compactMap { tip in
            joints[tip.joint].map { FingerTip(id: "\(id)-\(tip.name)", name: tip.name, location: $0) }
        }
    }
}

/// Owns the capture session and publishes the latest fingertip positions.
@Observable
final class CameraModel {
    let session = AVCaptureSession()
    private(set) var hands: [TrackedHand] = []
    /// Pixel size of the camera frames, used to aspect-fit the overlay.
    private(set) var videoSize: CGSize = CGSize(width: 16, height: 9)
    private(set) var errorMessage: String?
    /// True once inputs/outputs are attached, so a preview layer created now gets a live connection.
    private(set) var isConfigured = false

    @ObservationIgnored private var processor: FrameProcessor?

    func start() async {
        guard !isConfigured else { return }

        guard await AVCaptureDevice.requestAccess(for: .video) else {
            errorMessage = "Camera access was denied. Enable it in System Settings › Privacy & Security › Camera."
            return
        }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            errorMessage = "No camera is available."
            return
        }

        // A main-actor closure is Sendable, so the capture queue can hop back to it safely.
        let update: @MainActor ([TrackedHand], CGSize) -> Void = { [weak self] hands, size in
            guard let self else { return }
            self.hands = hands
            self.videoSize = size
        }
        let processor = FrameProcessor { hands, size in
            Task { @MainActor in update(hands, size) }
        }
        self.processor = processor

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(processor, queue: DispatchQueue(label: "FingerTracker.video"))

        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        isConfigured = true

        // startRunning blocks, so keep it off the main thread.
        let session = self.session
        await Task.detached { session.startRunning() }.value
    }
}

/// Runs hand pose detection on each camera frame (on the capture queue).
nonisolated final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()
    private let onResults: @Sendable ([TrackedHand], CGSize) -> Void

    /// The fingertip joints Vision reports, with the names used in `TrackedHand.joints`.
    private static let jointNames: [(VNHumanHandPoseObservation.JointName, String)] = [
        (.thumbTip, "thumbTip"), (.indexTip, "indexTip"), (.middleTip, "middleTip"),
        (.ringTip, "ringTip"), (.littleTip, "littleTip")
    ]

    init(onResults: @escaping @Sendable ([TrackedHand], CGSize) -> Void) {
        self.onResults = onResults
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return
        }

        let observations = request.results ?? []
        let hands = observations.enumerated().map { index, observation in
            var joints: [String: CGPoint] = [:]
            for (joint, name) in Self.jointNames {
                guard let point = try? observation.recognizedPoint(joint), point.confidence > 0.3 else { continue }
                // Vision uses a bottom-left origin; flip y for SwiftUI and flip x to match the mirrored preview.
                joints[name] = CGPoint(x: 1 - point.location.x, y: 1 - point.location.y)
            }
            return TrackedHand(id: index, joints: joints)
        }
        onResults(hands.filter { !$0.joints.isEmpty }, size)
    }
}
