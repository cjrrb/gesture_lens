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

    /// Joint chains from the wrist out to each fingertip, used to draw the skeleton.
    static let skeleton: [[String]] = [
        ["wrist", "thumbCMC", "thumbMP", "thumbIP", "thumbTip"],
        ["wrist", "indexMCP", "indexPIP", "indexDIP", "indexTip"],
        ["wrist", "middleMCP", "middlePIP", "middleDIP", "middleTip"],
        ["wrist", "ringMCP", "ringPIP", "ringDIP", "ringTip"],
        ["wrist", "littleMCP", "littlePIP", "littleDIP", "littleTip"]
    ]

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

/// A detected face.
struct TrackedFace: Identifiable {
    let id: Int
    /// Normalized bounding box (0–1) with a top-left origin, already mirrored to match the preview.
    let bounds: CGRect
}

/// Owns the capture session and publishes the latest fingertip positions.
@Observable
final class CameraModel {
    let session = AVCaptureSession()
    private(set) var hands: [TrackedHand] = []
    private(set) var faces: [TrackedFace] = []
    /// Pixel size of the camera frames, used to aspect-fit the overlay.
    private(set) var videoSize: CGSize = CGSize(width: 16, height: 9)
    private(set) var errorMessage: String?
    /// True once inputs/outputs are attached, so a preview layer created now gets a live connection.
    private(set) var isConfigured = false

    @ObservationIgnored private var processor: FrameProcessor?
    /// Last smoothed position for each hand joint, keyed by "<hand id>-<joint name>".
    @ObservationIgnored private var smoothedLocations: [String: CGPoint] = [:]
    /// Last smoothed bounding box for each face, keyed by `TrackedFace.id`.
    @ObservationIgnored private var smoothedFaceBounds: [Int: CGRect] = [:]

    /// How much of each new reading to blend in (lower = steadier but laggier).
    private static let smoothingFactor: CGFloat = 0.3
    /// Movements larger than this (normalized) snap immediately instead of easing in.
    private static let snapDistance: CGFloat = 0.15

    /// Applies exponential smoothing to hand joint positions to reduce frame-to-frame jitter.
    private func smoothed(_ hands: [TrackedHand]) -> [TrackedHand] {
        var updated: [String: CGPoint] = [:]
        let result = hands.map { hand in
            var joints: [String: CGPoint] = [:]
            for (name, raw) in hand.joints {
                let key = "\(hand.id)-\(name)"
                var location = raw
                if let previous = smoothedLocations[key],
                   hypot(location.x - previous.x, location.y - previous.y) < Self.snapDistance {
                    let a = Self.smoothingFactor
                    location = CGPoint(x: previous.x + a * (location.x - previous.x),
                                       y: previous.y + a * (location.y - previous.y))
                }
                updated[key] = location
                joints[name] = location
            }
            return TrackedHand(id: hand.id, joints: joints)
        }
        // Only keep joints seen this frame, so a reappearing joint starts fresh.
        smoothedLocations = updated
        return result
    }

    /// Applies the same smoothing to face bounding boxes.
    private func smoothed(_ faces: [TrackedFace]) -> [TrackedFace] {
        var updated: [Int: CGRect] = [:]
        let result = faces.map { face -> TrackedFace in
            var bounds = face.bounds
            if let previous = smoothedFaceBounds[face.id],
               hypot(bounds.midX - previous.midX, bounds.midY - previous.midY) < Self.snapDistance {
                let a = Self.smoothingFactor
                bounds = CGRect(x: previous.minX + a * (bounds.minX - previous.minX),
                                y: previous.minY + a * (bounds.minY - previous.minY),
                                width: previous.width + a * (bounds.width - previous.width),
                                height: previous.height + a * (bounds.height - previous.height))
            }
            updated[face.id] = bounds
            return TrackedFace(id: face.id, bounds: bounds)
        }
        smoothedFaceBounds = updated
        return result
    }

    /// The most recent unprocessed camera frame (not mirrored), if the camera is running.
    func currentFrame() -> CVPixelBuffer? {
        processor?.latestPixelBuffer()
    }

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
        let update: @MainActor ([TrackedHand], [TrackedFace], CGSize) -> Void = { [weak self] hands, faces, size in
            guard let self else { return }
            self.hands = smoothed(hands)
            self.faces = smoothed(faces)
            self.videoSize = size
        }
        let processor = FrameProcessor { hands, faces, size in
            Task { @MainActor in update(hands, faces, size) }
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

/// Runs hand pose and face detection on each camera frame (on the capture queue).
nonisolated final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()
    private let faceRequest = VNDetectFaceRectanglesRequest()
    /// The most recent camera frame, kept for taking photos. Written on the capture queue, read on the main actor.
    private let latestBufferLock = NSLock()
    private var latestBuffer: CVPixelBuffer?

    func latestPixelBuffer() -> CVPixelBuffer? {
        latestBufferLock.withLock { latestBuffer }
    }
    private let onResults: @Sendable ([TrackedHand], [TrackedFace], CGSize) -> Void

    /// Every hand joint Vision reports, with the names used in `TrackedHand.joints`.
    private static let jointNames: [(VNHumanHandPoseObservation.JointName, String)] = [
        (.wrist, "wrist"),
        (.thumbCMC, "thumbCMC"), (.thumbMP, "thumbMP"), (.thumbIP, "thumbIP"), (.thumbTip, "thumbTip"),
        (.indexMCP, "indexMCP"), (.indexPIP, "indexPIP"), (.indexDIP, "indexDIP"), (.indexTip, "indexTip"),
        (.middleMCP, "middleMCP"), (.middlePIP, "middlePIP"), (.middleDIP, "middleDIP"), (.middleTip, "middleTip"),
        (.ringMCP, "ringMCP"), (.ringPIP, "ringPIP"), (.ringDIP, "ringDIP"), (.ringTip, "ringTip"),
        (.littleMCP, "littleMCP"), (.littlePIP, "littlePIP"), (.littleDIP, "littleDIP"), (.littleTip, "littleTip")
    ]

    init(onResults: @escaping @Sendable ([TrackedHand], [TrackedFace], CGSize) -> Void) {
        self.onResults = onResults
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        latestBufferLock.withLock { latestBuffer = pixelBuffer }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request, faceRequest])
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
        let faces = (faceRequest.results ?? []).enumerated().map { index, observation in
            // Same conversion as fingertips: flip y for SwiftUI, mirror x to match the preview.
            let box = observation.boundingBox
            let bounds = CGRect(x: 1 - box.maxX, y: 1 - box.maxY, width: box.width, height: box.height)
            return TrackedFace(id: index, bounds: bounds)
        }
        onResults(hands.filter { !$0.joints.isEmpty }, faces, size)
    }
}
