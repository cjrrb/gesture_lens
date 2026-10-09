//
//  FingerSlider.swift
//  FingerTracker
//

import SwiftUI

/// A thin, terminal-style vertical slider. Display only — the value is driven by fingertip tracking.
struct FingerSlider: View {
    let value: Double
    /// `range.lowerBound` is at the bottom of the track, `range.upperBound` at the top.
    let range: ClosedRange<Double>
    let topLabel: String
    let bottomLabel: String
    /// True while a fingertip is controlling the slider.
    let isActive: Bool
    var format = "%.2f"
    /// When set, a color swatch is shown beside the thumb instead of the numeric value.
    var swatch: Color?
    /// Horizontal sliders put `range.lowerBound` on the left and `range.upperBound` on the right.
    var axis: Axis = .vertical

    var body: some View {
        switch axis {
        case .vertical: verticalBody
        case .horizontal: horizontalBody
        }
    }

    private var fraction: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    /// Thumb, filled while a fingertip is controlling the slider.
    private var thumb: some View {
        Circle()
            .stroke(.white, lineWidth: 0.75)
            .background(Circle().fill(.white.opacity(isActive ? 0.8 : 0)))
            .frame(width: 12, height: 12)
    }

    @ViewBuilder
    private func valueIndicator(at point: CGPoint) -> some View {
        if let swatch {
            Rectangle()
                .fill(swatch)
                .stroke(.white, lineWidth: 0.75)
                .frame(width: 12, height: 12)
                .position(point)
        } else {
            Text(String(format: format, value))
                .fixedSize()
                .position(point)
        }
    }

    private var horizontalBody: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let midY = geometry.size.height / 2
            let thumbX = fraction * width

            // Track with ticks at the left, middle, and right.
            Path { path in
                path.move(to: CGPoint(x: 0, y: midY))
                path.addLine(to: CGPoint(x: width, y: midY))
                for x in [0, width / 2, width] {
                    path.move(to: CGPoint(x: x, y: midY - 5))
                    path.addLine(to: CGPoint(x: x, y: midY + 5))
                }
            }
            .stroke(.white.opacity(0.6), lineWidth: 0.75)

            thumb.position(x: thumbX, y: midY)

            // Labels under each end; the value sits above the thumb.
            Text(bottomLabel)
                .fixedSize()
                .position(x: 0, y: midY + 16)
            Text(topLabel)
                .fixedSize()
                .position(x: width, y: midY + 16)
            valueIndicator(at: CGPoint(x: thumbX, y: midY - 18))
        }
        .font(.system(size: 10, weight: .thin, design: .monospaced))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.8), radius: 2)
        .animation(.easeOut(duration: 0.1), value: value)
    }

    private var verticalBody: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let midX = geometry.size.width / 2
            let thumbY = (1 - fraction) * height

            // Track with ticks at the top, middle, and bottom.
            Path { path in
                path.move(to: CGPoint(x: midX, y: 0))
                path.addLine(to: CGPoint(x: midX, y: height))
                for y in [0, height / 2, height] {
                    path.move(to: CGPoint(x: midX - 5, y: y))
                    path.addLine(to: CGPoint(x: midX + 5, y: y))
                }
            }
            .stroke(.white.opacity(0.6), lineWidth: 0.75)

            thumb.position(x: midX, y: thumbY)

            Text(topLabel)
                .fixedSize()
                .position(x: midX, y: -12)
            Text(bottomLabel)
                .fixedSize()
                .position(x: midX, y: height + 12)
            // The value sits to the right of the thumb.
            valueIndicator(at: CGPoint(x: midX + (swatch == nil ? 34 : 24), y: thumbY))
        }
        .font(.system(size: 10, weight: .thin, design: .monospaced))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.8), radius: 2)
        .animation(.easeOut(duration: 0.1), value: value)
    }
}

#Preview("Vertical") {
    FingerSlider(value: 0.4, range: -1...1, topLabel: "light", bottomLabel: "dark", isActive: true, format: "%+.2f")
        .frame(width: 24, height: 160)
        .padding(40)
        .background(.black)
}

#Preview("Horizontal") {
    FingerSlider(value: 0.6, range: 0...1, topLabel: "color", bottomLabel: "black", isActive: false,
                 swatch: Color(hue: 0.55, saturation: 0.85, brightness: 0.45), axis: .horizontal)
        .frame(width: 160, height: 24)
        .padding(40)
        .background(.black)
}
