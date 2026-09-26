import UIKit
import Photos

/// Opens Instagram's Stories composer with a run: a full background image (card, route, photo), or a
/// transparent sticker over Stride's dark colors that the runner can place on their own photo or video.
///
/// Instagram reads the images from the pasteboard and needs the app's Meta (Facebook) App ID as
/// `source_application` (``AppInfo/facebookAppID``). `instagram-stories` is listed in
/// LSApplicationQueriesSchemes so ``isInstalled`` can ask.
enum InstagramStories {
    private static let composer = URL(string: "instagram-stories://share")!

    static var isInstalled: Bool { UIApplication.shared.canOpenURL(composer) }

    /// Puts the image on the pasteboard for 5 minutes and opens Instagram. Returns false when
    /// Instagram couldn't be opened.
    static func share(_ image: UIImage, asSticker: Bool) async -> Bool {
        var components = URLComponents(url: composer, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "source_application", value: AppInfo.facebookAppID)]
        guard let url = components?.url else { return false }

        var item: [String: Any] = [
            "com.instagram.sharedSticker.backgroundTopColor": "#101419",
            "com.instagram.sharedSticker.backgroundBottomColor": "#0B0E12",
        ]
        if asSticker {
            guard let data = image.pngData() else { return false }
            item["com.instagram.sharedSticker.stickerImage"] = data
        } else {
            guard let data = image.jpegData(compressionQuality: 0.92) else { return false }
            item["com.instagram.sharedSticker.backgroundImage"] = data
        }
        UIPasteboard.general.setItems([item], options: [.expirationDate: Date.now.addingTimeInterval(5 * 60)])
        return await UIApplication.shared.open(url)
    }
}

/// Saves a share image to Photos, as a PNG when it's transparent so the sticker keeps its alpha.
enum PhotoSaver {
    enum Result { case saved, denied, failed }

    static func save(_ image: UIImage, transparent: Bool) async -> Result {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        guard let data = transparent ? image.pngData() : image.jpegData(compressionQuality: 0.95) else { return .failed }
        do {
            try await addToLibrary(data)
            return .saved
        } catch {
            return .failed
        }
    }

    /// Nonisolated so the change block isn't tied to the main actor: Photos runs it on its own queue,
    /// and the SDK doesn't mark it Sendable.
    nonisolated private static func addToLibrary(_ data: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}
