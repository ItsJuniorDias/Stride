import SwiftUI
import PhotosUI
import StrideKit
import StrideUI

/// Share a run, Instagram first: pick a Stories template (card, route, your photo, or a transparent
/// sticker), then send it straight to Stories, save it, or hand it to any app.
struct ShareRunSheet: View {
    let share: ShareRun
    @Environment(\.dismiss) private var dismiss
    @State private var template: StoryTemplate = .card
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    /// The current template as an image, redrawn when the template or photo changes.
    @State private var rendered: UIImage?
    @State private var status: String?
    @State private var isSharing = false
    @State private var isSaving = false

    private let previewScale: CGFloat = 0.62

    var body: some View {
        VStack(spacing: 0) {
            header
            preview
                .padding(.top, Space.x3)
            chips
                .padding(.top, Space.x4)
            contextLine
                .frame(minHeight: 22)
                .padding(.top, Space.x2)
            Spacer(minLength: Space.x4)
            actions
        }
        .padding(.horizontal, Space.x4)
        .padding(.bottom, Space.x3)
        .background(Color.surface)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: template)
        .task(id: template) { render() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photo = image
                    render()
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Share your run").font(.title2.bold()).foregroundStyle(.ink)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.inkMuted)
                    .frame(width: 30, height: 30)
                    .background(Color.surfaceRaised, in: Circle())
                    .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.top, Space.x4)
    }

    /// The template at the size it's shared, scaled down.
    private var preview: some View {
        Group {
            switch template {
            case .card: StoryCardView(share: share)
            case .route: StoryRouteView(share: share)
            case .photo: StoryPhotoView(share: share, photo: photo)
            case .sticker: StoryStickerPreview(share: share)
            }
        }
        .environment(\.colorScheme, .dark)
        .scaleEffect(previewScale)
        .frame(width: StoryLayout.size.width * previewScale, height: StoryLayout.size.height * previewScale)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md + 2, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 10)
        .accessibilityElement()
        .accessibilityLabel("\(template.title) preview")
    }

    private var chips: some View {
        HStack(spacing: Space.x2) {
            ForEach(StoryTemplate.allCases) { item in
                SelectableChip(item.title, isSelected: template == item) { template = item }
            }
        }
    }

    @ViewBuilder private var contextLine: some View {
        switch template {
        case .photo:
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(photo == nil ? "Choose photo" : "Change photo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.lane)
            }
        case .sticker:
            Text("Place it over any photo or video in Instagram.")
                .font(.footnote)
                .foregroundStyle(.inkMuted)
        case .card, .route:
            if let status {
                Text(status).font(.footnote).foregroundStyle(.inkMuted)
            } else {
                Color.clear
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Space.x3) {
            if let status, template == .photo || template == .sticker {
                Text(status).font(.footnote).foregroundStyle(.inkMuted)
            }
            Button {
                Task { await shareToInstagram() }
            } label: {
                Label {
                    Text("Share to Instagram Stories")
                } icon: {
                    StoriesGlyph()
                }
            }
            .buttonStyle(.stridePrimary)
            .disabled(isSharing || !canShare)

            HStack(spacing: Space.x3) {
                Button {
                    Task { await save() }
                } label: {
                    Label(isSaving ? "Saving…" : "Save image", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.strideSecondary)
                .disabled(isSaving || !canShare)

                if let rendered {
                    let image = Image(uiImage: rendered)
                    ShareLink(item: image, preview: SharePreview(share.title, image: image)) {
                        Label("More", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.strideSecondary)
                } else {
                    Button {} label: { Label("More", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.strideSecondary)
                        .disabled(true)
                }
            }
        }
    }

    /// The photo template needs a photo first.
    private var canShare: Bool {
        rendered != nil && !(template == .photo && photo == nil)
    }

    private func render() {
        status = nil
        rendered = StoryRenderer.image(for: template, share: share, photo: photo)
    }

    private func shareToInstagram() async {
        guard let rendered else { return }
        guard InstagramStories.isInstalled else {
            status = "Instagram isn't installed. Save the image or use More."
            return
        }
        isSharing = true
        defer { isSharing = false }
        if !(await InstagramStories.share(rendered, asSticker: template.isTransparent)) {
            status = "Couldn't open Instagram. Save the image and post it from there."
        }
    }

    private func save() async {
        guard let rendered else { return }
        isSaving = true
        defer { isSaving = false }
        switch await PhotoSaver.save(rendered, transparent: template.isTransparent) {
        case .saved: status = "Saved to Photos."
        case .denied: status = "Allow Stride to add photos in Settings to save images."
        case .failed: status = "Couldn't save the image. Try again."
        }
    }
}

/// A camera-in-a-rounded-square mark for the Stories button (not Instagram's logo, which Stride
/// can't use).
private struct StoriesGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .stroke(lineWidth: 2)
            Circle()
                .stroke(lineWidth: 2)
                .frame(width: 8.4, height: 8.4)
            Circle()
                .frame(width: 2.2, height: 2.2)
                .offset(x: 5.3, y: -5.3)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

#Preview {
    ShareRunSheet(share: .preview)
}
