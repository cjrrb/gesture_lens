//
//  TrackingOverlay.swift
//  FingerTracker
//

import SwiftUI

/// Draws the face boxes and hand skeletons over the video.
struct TrackingOverlay: View {
    let hands: [TrackedHand]
    let faces: [TrackedFace]
    let showsSkeleton: Bool
    /// The video's rectangle in this view's coordinates; normalized positions are mapped into it.
    let rect: CGRect
    /// When the skeleton is hidden, draw small index-fingertip pointers for aiming at controls (live view only).
    var showsPointers = false

    var body: some View {
        ZStack {
            ForEach(faces) { face in
                let box = viewRect(for: face)
                Rectangle()
                    .stroke(.white, lineWidth: 0.75)
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
                label(Self.formatted(CGPoint(x: face.bounds.midX, y: face.bounds.midY)))
                    .position(x: box.midX, y: box.minY - 10)
            }
            if showsSkeleton {
                ForEach(hands) { hand in
                    skeleton(for: hand)
                }
            } else if showsPointers {
                // Skeleton hidden: tracking still drives the controls, so keep a small pointer
                // on each index fingertip to aim at sliders and buttons.
                ForEach(hands) { hand in
                    if let indexTip = hand.joints["indexTip"] {
                        Circle()
                            .stroke(.white.opacity(0.6), lineWidth: 0.75)
                            .frame(width: 10, height: 10)
                            .position(viewPoint(for: indexTip))
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func skeleton(for hand: TrackedHand) -> some View {
        // From the wrist through each knuckle out to every fingertip.
        // Joints Vision couldn't see are skipped, joining the neighbors on either side.
        Path { path in
            for chain in TrackedHand.skeleton {
                path.addLines(chain.compactMap { hand.joints[$0] }.map(viewPoint(for:)))
            }
        }
        .stroke(.white.opacity(0.8), lineWidth: 0.75)
        // Small dots on the wrist and knuckles (fingertips get the larger rings below).
        ForEach(hand.joints.filter { !$0.key.hasSuffix("Tip") }.map(\.key), id: \.self) { name in
            if let location = hand.joints[name] {
                Circle()
                    .fill(.white)
                    .frame(width: 3, height: 3)
                    .position(viewPoint(for: location))
            }
        }
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

    /// Converts a face's normalized bounds into a rectangle within the video rectangle.
    private func viewRect(for face: TrackedFace) -> CGRect {
        CGRect(x: rect.minX + face.bounds.minX * rect.width,
               y: rect.minY + face.bounds.minY * rect.height,
               width: face.bounds.width * rect.width,
               height: face.bounds.height * rect.height)
    }

    static func formatted(_ point: CGPoint) -> String {
        String(format: "%.2f %.2f", point.x, point.y)
    }
}
