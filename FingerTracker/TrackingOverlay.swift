//
//  TrackingOverlay.swift
//  FingerTracker
//

import SwiftUI

/// Draws the tracked fingertips over the video.
struct TrackingOverlay: View {
    let hands: [TrackedHand]
    /// The video's rectangle in this view's coordinates; normalized positions are mapped into it.
    let rect: CGRect

    var body: some View {
        ZStack {
            ForEach(hands) { hand in
                fingertips(for: hand)
            }
        }
        .foregroundStyle(.white)
    }

    /// A thin ring on each fingertip with its coordinates above it.
    @ViewBuilder
    private func fingertips(for hand: TrackedHand) -> some View {
        ForEach(hand.fingers) { finger in
            let point = viewPoint(for: finger.location)
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 0.75)
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(.white)
                    .frame(width: 2, height: 2)
            }
            .position(point)
            label(Self.formatted(finger.location))
                .position(x: point.x, y: point.y - 20)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .thin, design: .monospaced))
            .shadow(color: .black.opacity(0.8), radius: 2)
            .fixedSize()
    }

    /// Converts a normalized location into a point within the video rectangle.
    private func viewPoint(for location: CGPoint) -> CGPoint {
        CGPoint(x: rect.minX + location.x * rect.width, y: rect.minY + location.y * rect.height)
    }

    static func formatted(_ point: CGPoint) -> String {
        String(format: "%.2f %.2f", point.x, point.y)
    }
}
