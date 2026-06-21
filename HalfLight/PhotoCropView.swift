//
//  PhotoCropView.swift
//  HalfLight
//
//  A simple circular photo cropper for profile pictures: the picked image fills a
//  round window the dreamer can drag and pinch to frame, then "Use Photo" renders
//  the framed region to a compact square image (shown as a circle elsewhere).
//

#if canImport(UIKit)
import SwiftUI
import UIKit

struct PhotoCropView: View {
    let imageData: Data
    /// Called with the cropped JPEG when the dreamer confirms.
    let onComplete: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    /// On-screen diameter of the crop window, and the exported pixel size.
    private let cropDiameter: CGFloat = 300
    private let outputSize: CGFloat = 512

    private var sourceImage: UIImage? { UIImage(data: imageData) }

    /// Whether the dreamer has zoomed or panned away from the default framing.
    private var isAdjusted: Bool { scale != 1 || offset != .zero }

    private func reset() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = sourceImage {
                VStack(spacing: 24) {
                    Spacer()

                    cropWindow(image)

                    Text("Drag to reposition · pinch to zoom")
                        .font(.dreamBody(13))
                        .foregroundStyle(.white.opacity(0.65))

                    if isAdjusted {
                        Button(action: reset) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                                .font(.dreamBody(13, .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.white.opacity(0.14), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }

                    Spacer()

                    actions(image)
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 24)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
    }

    // MARK: - Crop window

    private func cropWindow(_ image: UIImage) -> some View {
        framedImage(image)
            .frame(width: cropDiameter, height: cropDiameter)
            .clipped()
            .overlay {
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .reverseMask { Circle() }
                    .allowsHitTesting(false)
            }
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .frame(width: cropDiameter, height: cropDiameter)
            .contentShape(Rectangle())
            .gesture(dragGesture(image))
            .simultaneousGesture(zoomGesture(image))
    }

    private func framedImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: cropDiameter, height: cropDiameter)
            .scaleEffect(scale)
            .offset(offset)
    }

    // MARK: - Gestures

    private func zoomGesture(_ image: UIImage) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 6)
                offset = clamped(offset, image: image)
            }
            .onEnded { _ in
                lastScale = scale
                lastOffset = offset
            }
    }

    private func dragGesture(_ image: UIImage) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clamped(proposed, image: image)
            }
            .onEnded { _ in lastOffset = offset }
    }

    /// Keep the image covering the whole circle — no empty corners.
    private func clamped(_ proposed: CGSize, image: UIImage) -> CGSize {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return .zero }
        let fill = cropDiameter / min(size.width, size.height)
        let displayedWidth = size.width * fill * scale
        let displayedHeight = size.height * fill * scale
        let maxX = max(0, (displayedWidth - cropDiameter) / 2)
        let maxY = max(0, (displayedHeight - cropDiameter) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    // MARK: - Actions

    private func actions(_ image: UIImage) -> some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Text("Cancel")
                    .font(.dreamBody(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.white.opacity(0.14), in: .rect(cornerRadius: DreamMetric.controlRadius))
            }
            .buttonStyle(.plain)

            Button { save(image) } label: {
                Text("Use Photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    @MainActor
    private func save(_ image: UIImage) {
        let renderer = ImageRenderer(
            content: framedImage(image)
                .frame(width: cropDiameter, height: cropDiameter)
                .clipped()
        )
        renderer.scale = outputSize / cropDiameter
        if let cropped = renderer.uiImage?.jpegData(compressionQuality: 0.85) {
            onComplete(cropped)
        }
        dismiss()
    }
}

private extension View {
    /// Punch the shape out of the view (the inverse of `.mask`), used to dim
    /// everything outside the circular crop window.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
#endif
