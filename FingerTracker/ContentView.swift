//
//  ContentView.swift
//  FingerTracker
//
//  Created by Cort Reynolds-Bolan on 2026-10-08.
//

import SwiftUI

/// The finger-controlled sliders overlaid on the video.
private enum SliderKind: CaseIterable {
    case brightness, grain, hue, saturation, vignetteColor
}

/// The start of a fingertip drag on a slider; the value moves relative to this, so grabbing never jumps it.
private struct SliderGrab {
    /// Finger position along the slider's axis when grabbed, as a fraction of the slider's length.
    let startPosition: CGFloat
    let startFraction: Double
}

/// Tracks a fingertip "tap" on an on-screen button: the finger must rest on the button briefly to tap it,
/// then leave before it can tap again, so resting doesn't repeat.
private struct FingerButtonState {
    /// When a fingertip started resting on the button (before it counts as a tap).
    var hoverStart: Date?
    var needsRelease = false

    /// Returns true when this update completes a tap.
    mutating func update(with points: [CGPoint], in frame: CGRect, delay: TimeInterval) -> Bool {
        guard points.contains(where: { frame.contains($0) }) else {
            hoverStart = nil
            needsRelease = false
            return false
        }
        guard !needsRelease else { return false }
        let now = Date.now
        let start = hoverStart ?? now
        hoverStart = start
        guard now.timeIntervalSince(start) >= delay else { return false }
        hoverStart = nil
        needsRelease = true
        return true
    }
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
    @State private var isVignetteOn = false
    /// 0 … 1 slider position for the vignette color; the bottom section is black, above it runs through the hues.
    @State private var vignetteTone: Double = 0
    @State private var vignetteButton = FingerButtonState()
    @State private var photoButton = FingerButtonState()
    /// The number shown during the photo countdown (3, 2, 1), or nil when not counting down.
    @State private var countdown: Int?
    /// How much of the countdown ring is drawn (1 → 0 over each second).
    @State private var countdownProgress: CGFloat = 1
    /// Briefly true right as a photo is taken, for the white flash.
    @State private var isFlashing = false
    /// A short message after taking a photo (where it was saved, or what went wrong).
    @State private var photoStatus: String?

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
                vignetteOverlay
                grainOverlay
                sliders
                fingerOverlay
                photoOverlay
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

    /// Darkened edges over the video area, faded in and out by the vignette button.
    private var vignetteOverlay: some View {
        GeometryReader { geometry in
            let rect = videoRect(in: geometry.size)
            EllipticalGradient(colors: [.clear, vignetteColor.opacity(0.8)], center: .center,
                               startRadiusFraction: 0.3, endRadiusFraction: 0.75)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .opacity(isVignetteOn ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: isVignetteOn)
        }
        .allowsHitTesting(false)
    }

    /// All sliders and the vignette button, driven by index fingertips hovering over them.
    private var sliders: some View {
        GeometryReader { geometry in
            let rect = videoRect(in: geometry.size)
            ForEach(SliderKind.allCases, id: \.self) { kind in
                let frame = sliderFrame(for: kind, in: rect)
                slider(for: kind)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
            let vignetteFrame = vignetteButtonFrame(in: rect)
            fingerButton(isVignetteOn ? "[x] vignette" : "[ ] vignette", state: vignetteButton, frame: vignetteFrame)
            let photoFrame = photoButtonFrame(in: rect)
            fingerButton(countdown.map { "[ \($0) ]" } ?? "[ snap ]", state: photoButton, frame: photoFrame)
            Color.clear
                .onChange(of: model.hands.compactMap { $0.joints["indexTip"] }.map { viewPoint(for: $0, in: rect) }) { _, points in
                    for kind in SliderKind.allCases {
                        updateSlider(kind, with: points, in: sliderFrame(for: kind, in: rect))
                    }
                    if vignetteButton.update(with: points, in: vignetteFrame, delay: Self.grabDelay) {
                        isVignetteOn.toggle()
                    }
                    if photoButton.update(with: points, in: photoFrame, delay: Self.grabDelay) {
                        startPhotoCountdown()
                    }
                }
        }
        .allowsHitTesting(false)
    }

    /// A thin outlined button that lights up while a fingertip rests on it.
    private func fingerButton(_ title: String, state: FingerButtonState, frame: CGRect) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .thin, design: .monospaced))
            .shadow(color: .black.opacity(0.8), radius: 2)
            .frame(width: frame.width, height: frame.height)
            .overlay(Rectangle().stroke(.white, lineWidth: 0.75))
            .background(Rectangle().fill(.white.opacity(state.hoverStart != nil ? 0.2 : 0)))
            .position(x: frame.midX, y: frame.midY)
    }

    /// A small button in the top-right corner of the video.
    private func photoButtonFrame(in rect: CGRect) -> CGRect {
        CGRect(x: rect.maxX - 32 - 72, y: rect.minY + 40, width: 72, height: 32)
    }

    /// The countdown, the capture flash, and the save message.
    private var photoOverlay: some View {
        GeometryReader { geometry in
            let rect = videoRect(in: geometry.size)
            if let countdown {
                // Terminal-style countdown: a thin ring that empties over each second around a bracketed number.
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.25), lineWidth: 0.75)
                    Circle()
                        .trim(from: 0, to: countdownProgress)
                        .stroke(.white, lineWidth: 0.75)
                        .rotationEffect(.degrees(-90))
                    Text("[ \(countdown) ]")
                        .font(.system(size: 28, weight: .thin, design: .monospaced))
                        .contentTransition(.numericText(countsDown: true))
                    Text("> capturing_")
                        .font(.system(size: 10, weight: .thin, design: .monospaced))
                        .opacity(0.7)
                        .offset(y: 80)
                }
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.8), radius: 2)
                .position(x: rect.midX, y: rect.midY)
                .transition(.opacity)
            }
            Rectangle()
                .fill(.white)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .opacity(isFlashing ? 0.9 : 0)
            if let photoStatus {
                Text(photoStatus)
                    .font(.system(size: 11, weight: .thin, design: .monospaced))
                    .shadow(color: .black.opacity(0.8), radius: 2)
                    .fixedSize()
                    .position(x: rect.midX, y: rect.maxY - 24)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    /// Counts down 3, 2, 1 in the middle of the screen, then takes the photo. Ignored if already counting.
    private func startPhotoCountdown() {
        guard countdown == nil else { return }
        Task {
            for number in [3, 2, 1] {
                // Refill the ring instantly, give SwiftUI a frame to draw it full, then drain it over the second.
                countdownProgress = 1
                withAnimation(.easeOut(duration: 0.3)) { countdown = number }
                try? await Task.sleep(for: .milliseconds(20))
                withAnimation(.linear(duration: 0.98)) { countdownProgress = 0 }
                try? await Task.sleep(for: .milliseconds(980))
            }
            withAnimation(.easeOut(duration: 0.2)) { countdown = nil }
            takePhoto()
            isFlashing = true
            withAnimation(.easeOut(duration: 0.5)) { isFlashing = false }
        }
    }

    /// Renders the current frame with all effects applied and saves it to ~/Pictures/snap_shots.
    private func takePhoto() {
        let settings = PhotoSettings(brightness: brightness, grain: grain, hue: hue, saturation: saturation,
                                     vignetteColor: isVignetteOn ? vignetteColor : nil)
        let message: String
        if let frame = model.currentFrame(), let image = PhotoRenderer.render(frame, settings: settings) {
            do {
                let url = try PhotoRenderer.saveToPictures(image)
                message = "> saved ~/Pictures/\(PhotoRenderer.folderName)/\(url.lastPathComponent)"
            } catch {
                message = "> couldn't save photo: \(error.localizedDescription)"
            }
        } else {
            message = "> couldn't capture photo"
        }
        withAnimation { photoStatus = message }
        Task {
            try? await Task.sleep(for: .seconds(3))
            // Only clear this message, not a newer one from a later photo.
            if photoStatus == message {
                withAnimation { photoStatus = nil }
            }
        }
    }

    /// Length of the horizontal vignette color slider: a fifth of the video's width.
    private func vignetteSliderLength(in rect: CGRect) -> CGFloat {
        rect.width / 5
    }

    /// Sits near the bottom-left corner, raised off the bottom edge where hands are harder to track,
    /// and centered under the vignette color slider.
    private func vignetteButtonFrame(in rect: CGRect) -> CGRect {
        let width: CGFloat = 96
        let sliderMidX = rect.minX + 32 + vignetteSliderLength(in: rect) / 2
        return CGRect(x: sliderMidX - width / 2, y: rect.maxY - 80 - 36, width: width, height: 36)
    }

    /// The slider's bottom 10% picks black; above that it sweeps hues from red through to magenta.
    private var vignetteColor: Color {
        guard vignetteTone >= 0.1 else { return .black }
        return Color(hue: (vignetteTone - 0.1) / 0.9 * 0.9, saturation: 0.85, brightness: 0.45)
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
        case .vignetteColor:
            return FingerSlider(value: vignetteTone, range: 0...1, topLabel: "color", bottomLabel: "black",
                                isActive: isActive, swatch: vignetteColor, axis: .horizontal)
        }
    }

    /// ±150° rather than ±180°, so the two ends of the hue slider are visibly different colors
    /// (a full ±180° would make the top and bottom the same hue).
    private static let hueRange: ClosedRange<Double> = -150...150

    /// Only the vignette color slider runs left to right; the rest are vertical.
    private func isHorizontal(_ kind: SliderKind) -> Bool {
        kind == .vignetteColor
    }

    /// Maps a slider position (0 = bottom/left, 1 = top/right) onto the slider's value range.
    private func setValue(fromFraction fraction: Double, for kind: SliderKind) {
        switch kind {
        case .brightness: brightness = fraction * 2 - 1
        case .grain: grain = fraction
        case .hue: hue = Self.hueRange.lowerBound + fraction * (Self.hueRange.upperBound - Self.hueRange.lowerBound)
        case .saturation: saturation = fraction * 2
        case .vignetteColor: vignetteTone = fraction
        }
    }

    /// The slider's current value as a position (0 = bottom/left, 1 = top/right), i.e. where its thumb is.
    private func valueFraction(for kind: SliderKind) -> Double {
        switch kind {
        case .brightness: (brightness + 1) / 2
        case .grain: grain
        case .hue: (hue - Self.hueRange.lowerBound) / (Self.hueRange.upperBound - Self.hueRange.lowerBound)
        case .saturation: saturation / 2
        case .vignetteColor: vignetteTone
        }
    }

    /// Brightness and grain sit in the top-left; hue and saturation in the bottom-right;
    /// the horizontal vignette color slider sits just above the vignette button.
    /// Vertical sliders are a quarter of the video's height; the horizontal one a fifth of its width.
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
        case .vignetteColor:
            // Leave room between the track and the button for its end labels.
            let button = vignetteButtonFrame(in: rect)
            return CGRect(x: rect.minX + 32, y: button.minY - 48, width: vignetteSliderLength(in: rect), height: width)
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
        let horizontal = isHorizontal(kind)
        // Position along the slider's axis, as a fraction of its length (up and right are positive).
        func alongAxis(_ point: CGPoint) -> CGFloat {
            horizontal ? point.x / frame.width : -point.y / frame.height
        }

        if let grab = grabs[kind] {
            let onTrack = points.first { point in
                if horizontal {
                    abs(point.y - frame.midY) < 28 && point.x > frame.minX - 24 && point.x < frame.maxX + 24
                } else {
                    abs(point.x - frame.midX) < 28 && point.y > frame.minY - 24 && point.y < frame.maxY + 24
                }
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
        let thumb = horizontal
            ? CGPoint(x: frame.minX + thumbFraction * frame.width, y: frame.midY)
            : CGPoint(x: frame.midX, y: frame.minY + (1 - thumbFraction) * frame.height)
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
