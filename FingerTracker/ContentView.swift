//
//  ContentView.swift
//  FingerTracker
//
//  Created by Cort Reynolds-Bolan on 2026-10-08.
//

import SwiftUI

/// The finger-controlled sliders overlaid on the video.
private enum SliderKind: CaseIterable {
    case brightness, grain, hue, saturation
}

/// The start of a fingertip drag on a slider; the value moves relative to this, so grabbing never jumps it.
private struct SliderGrab {
    /// Finger position along the slider's axis when grabbed, as a fraction of the slider's length.
    let startPosition: CGFloat
    let startFraction: Double
}

struct ContentView: View {
    @State private var model = CameraModel()
    /// -1 (dark) … 1 (light).
    @State private var brightness: Double = 0
    /// 0 (none) … 1 (heavy).
    @State private var grain: Double = 0
    /// Hue rotation in degrees, within `hueRange`.
    @State private var hue: Double = 0
    /// Saturation multiplier, 0 (grayscale) … 2 (double).
    @State private var saturation: Double = 1
    /// Sliders currently grabbed by a fingertip, with where the drag started.
    @State private var grabs: [SliderKind: SliderGrab] = [:]
    /// When a fingertip started resting on each slider's thumb (before it counts as a grab).
    @State private var hoverStarts: [SliderKind: Date] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black
                // Mirror the feed so it behaves like a mirror; the overlay's x coordinates are flipped to match.
                if model.isConfigured {
                    // Pin the preview to the same rect the overlays use, so filters and tracking always line up.
                    GeometryReader { geometry in
                        let rect = videoRect(in: geometry.size)
                        CameraPreview(session: model.session, hue: hue, saturation: saturation)
                            .scaleEffect(x: -1, y: 1)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                brightnessTint
                grainOverlay
                sliders
                fingerOverlay
                if let errorMessage = model.errorMessage {
                    Text("> \(errorMessage)")
                        .padding()
                }
            }
            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 0.5)
            positionList
                .frame(width: 240)
        }
        .font(.system(size: 12, weight: .thin, design: .monospaced))
        .foregroundStyle(.white)
        .background(.black)
        .preferredColorScheme(.dark)
        .frame(minWidth: 800, minHeight: 500)
        .task { await model.start() }
    }

    /// White or black tint over the video area to lighten or darken the camera image.
    private var brightnessTint: some View {
        GeometryReader { geometry in
            let rect = videoRect(in: geometry.size)
            Rectangle()
                .fill(brightness >= 0 ? Color.white.opacity(brightness * 0.6) : Color.black.opacity(-brightness * 0.85))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
        .allowsHitTesting(false)
    }

    /// Animated film grain over the video area.
    private var grainOverlay: some View {
        GeometryReader { geometry in
            let rect = videoRect(in: geometry.size)
            // The top of the slider maps to 40% grain opacity.
            GrainOverlay(intensity: grain * 0.4)
                .frame(width: rect.width, height: rect.height)
                .clipped()
                .position(x: rect.midX, y: rect.midY)
        }
        .allowsHitTesting(false)
    }

    /// All sliders, driven by index fingertips hovering over them.
    private var sliders: some View {
        GeometryReader { geometry in
            let rect = videoRect(in: geometry.size)
            ForEach(SliderKind.allCases, id: \.self) { kind in
                let frame = sliderFrame(for: kind, in: rect)
                slider(for: kind)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
            Color.clear
                .onChange(of: model.hands.compactMap { $0.joints["indexTip"] }.map { viewPoint(for: $0, in: rect) }) { _, points in
                    for kind in SliderKind.allCases {
                        updateSlider(kind, with: points, in: sliderFrame(for: kind, in: rect))
                    }
                }
        }
        .allowsHitTesting(false)
    }

    private func slider(for kind: SliderKind) -> FingerSlider {
        let isActive = grabs[kind] != nil
        switch kind {
        case .brightness:
            return FingerSlider(value: brightness, range: -1...1, topLabel: "light", bottomLabel: "dark",
                                isActive: isActive, format: "%+.2f")
        case .grain:
            return FingerSlider(value: grain, range: 0...1, topLabel: "grain", bottomLabel: "none", isActive: isActive)
        case .hue:
            return FingerSlider(value: hue, range: Self.hueRange, topLabel: "hue+", bottomLabel: "hue-",
                                isActive: isActive, format: "%+.0f°")
        case .saturation:
            return FingerSlider(value: saturation, range: 0...2, topLabel: "vivid", bottomLabel: "mono", isActive: isActive)
        }
    }

    /// ±150° rather than ±180°, so the two ends of the hue slider are visibly different colors
    /// (a full ±180° would make the top and bottom the same hue).
    private static let hueRange: ClosedRange<Double> = -150...150

    /// Maps a slider position (0 = bottom, 1 = top) onto the slider's value range.
    private func setValue(fromFraction fraction: Double, for kind: SliderKind) {
        switch kind {
        case .brightness: brightness = fraction * 2 - 1
        case .grain: grain = fraction
        case .hue: hue = Self.hueRange.lowerBound + fraction * (Self.hueRange.upperBound - Self.hueRange.lowerBound)
        case .saturation: saturation = fraction * 2
        }
    }

    /// The slider's current value as a position (0 = bottom, 1 = top), i.e. where its thumb is.
    private func valueFraction(for kind: SliderKind) -> Double {
        switch kind {
        case .brightness: (brightness + 1) / 2
        case .grain: grain
        case .hue: (hue - Self.hueRange.lowerBound) / (Self.hueRange.upperBound - Self.hueRange.lowerBound)
        case .saturation: saturation / 2
        }
    }

    /// Brightness and grain sit in the top-left; hue and saturation in the bottom-right.
    /// Each slider is a quarter of the video's height.
    private func sliderFrame(for kind: SliderKind, in rect: CGRect) -> CGRect {
        let width: CGFloat = 24
        let height = rect.height / 4
        let top = rect.minY + 40
        let bottom = rect.maxY - 40 - height
        switch kind {
        case .brightness: return CGRect(x: rect.minX + 32, y: top, width: width, height: height)
        case .grain: return CGRect(x: rect.minX + 128, y: top, width: width, height: height)
        // Leave room on the right for each slider's value label.
        case .hue: return CGRect(x: rect.maxX - 176, y: bottom, width: width, height: height)
        case .saturation: return CGRect(x: rect.maxX - 80, y: bottom, width: width, height: height)
        }
    }

    /// How long a fingertip must rest on a thumb before it grabs it, so fingers passing over don't.
    private static let grabDelay: TimeInterval = 0.25

    /// Drives one slider from the current index fingertip positions.
    ///
    /// The value only changes by dragging the thumb: a fingertip has to rest on the thumb briefly to grab it,
    /// then the value moves by however far the finger moves from where it grabbed (never jumping to the
    /// finger's position). The grab is released when the finger leaves the track.
    private func updateSlider(_ kind: SliderKind, with points: [CGPoint], in frame: CGRect) {
        // Position along the slider, as a fraction of its length (up is positive).
        func alongAxis(_ point: CGPoint) -> CGFloat {
            -point.y / frame.height
        }

        if let grab = grabs[kind] {
            let onTrack = points.first { point in
                abs(point.x - frame.midX) < 28 && point.y > frame.minY - 24 && point.y < frame.maxY + 24
            }
            guard let point = onTrack else {
                grabs[kind] = nil
                return
            }
            let fraction = grab.startFraction + (alongAxis(point) - grab.startPosition)
            setValue(fromFraction: min(max(fraction, 0), 1), for: kind)
            return
        }

        let thumbFraction = valueFraction(for: kind)
        let thumb = CGPoint(x: frame.midX, y: frame.minY + (1 - thumbFraction) * frame.height)
        guard let point = points.first(where: { hypot($0.x - thumb.x, $0.y - thumb.y) < 24 }) else {
            hoverStarts[kind] = nil
            return
        }
        let now = Date.now
        let hoverStart = hoverStarts[kind] ?? now
        hoverStarts[kind] = hoverStart
        if now.timeIntervalSince(hoverStart) >= Self.grabDelay {
            grabs[kind] = SliderGrab(startPosition: alongAxis(point), startFraction: thumbFraction)
            hoverStarts[kind] = nil
        }
    }

    /// The face box and hand skeleton.
    private var fingerOverlay: some View {
        GeometryReader { geometry in
            TrackingOverlay(hands: model.hands, faces: model.faces, rect: videoRect(in: geometry.size))
        }
        .allowsHitTesting(false)
    }

    /// Terminal-style sidebar listing every tracked finger's position.
    private var positionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("finger_tracker")
                Text(String(repeating: "─", count: 28))
                    .opacity(0.4)
                if model.faces.isEmpty && model.hands.isEmpty {
                    Text("> nothing detected_")
                        .opacity(0.6)
                }
                ForEach(model.faces) { face in
                    Text("[face \(face.id + 1)]")
                        .padding(.top, 8)
                    HStack {
                        Text("  center")
                        Spacer()
                        Text(formatted(CGPoint(x: face.bounds.midX, y: face.bounds.midY)))
                            .opacity(0.7)
                    }
                    HStack {
                        Text("  size")
                        Spacer()
                        Text(formatted(CGPoint(x: face.bounds.width, y: face.bounds.height)))
                            .opacity(0.7)
                    }
                }
                ForEach(model.hands) { hand in
                    Text("[hand \(hand.id + 1)]")
                        .padding(.top, 8)
                    ForEach(hand.fingers) { finger in
                        HStack {
                            Text("  \(finger.name.lowercased())")
                            Spacer()
                            Text(formatted(finger.location))
                                .opacity(0.7)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.black)
    }

    /// The aspect-fit rectangle the video occupies inside the given container size.
    private func videoRect(in size: CGSize) -> CGRect {
        let videoAspect = model.videoSize.width / model.videoSize.height
        let containerAspect = size.width / size.height
        if containerAspect > videoAspect {
            let width = size.height * videoAspect
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        } else {
            let height = size.width / videoAspect
            return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
        }
    }

    /// Converts a normalized location into a point within the video rectangle.
    private func viewPoint(for location: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + location.x * rect.width,
                y: rect.minY + location.y * rect.height)
    }

    private func formatted(_ point: CGPoint) -> String {
        TrackingOverlay.formatted(point)
    }
}

#Preview {
    ContentView()
}
