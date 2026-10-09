//
//  ContentView.swift
//  FingerTracker
//
//  Created by Cort Reynolds-Bolan on 2026-10-08.
//

import SwiftUI

struct ContentView: View {
    @State private var model = CameraModel()

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black
                // Mirror the feed so it behaves like a mirror; the overlay's x coordinates are flipped to match.
                if model.isConfigured {
                    // Pin the preview to the same rect the overlays use, so filters and tracking always line up.
                    GeometryReader { geometry in
                        let rect = videoRect(in: geometry.size)
                        CameraPreview(session: model.session)
                            .scaleEffect(x: -1, y: 1)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
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

    /// The face box and thin rings and coordinates over each tracked fingertip.
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

    private func formatted(_ point: CGPoint) -> String {
        TrackingOverlay.formatted(point)
    }
}

#Preview {
    ContentView()
}
