import SpriteKit
import UIKit

/// Atlas identifiers matching asset-catalog sprite atlases / `*.atlas` folders.
enum CompanionAtlasID: String, CaseIterable, Sendable {
    case working = "Working"
    case typing = "Typing"
    case deepFocus = "DeepFocus"
    case completed = "Completed"
    case expired = "Expired"

    var framePrefix: String {
        switch self {
        case .working: return "working"
        case .typing: return "typing"
        case .deepFocus: return "deepfocus"
        case .completed: return "completed"
        case .expired: return "expired"
        }
    }

    var expectedFrameCount: Int { self == .typing ? 20 : 12 }
}

/// Loads and preloads companion sprite frames once. Texture order follows filename sort.
final class CompanionTextureStore {
    static let shared = CompanionTextureStore()

    private let lock = NSLock()
    private var texturesByAtlas: [CompanionAtlasID: [SKTexture]] = [:]
    private var didStartPreload = false

    private init() {}

    /// Synchronously materializes ordered textures, then kicks off GPU preload.
    func preloadIfNeeded() {
        lock.lock()
        let already = didStartPreload
        if !already { didStartPreload = true }
        lock.unlock()

        for id in CompanionAtlasID.allCases {
            _ = textures(for: id)
        }

        guard !already else { return }
        let atlases = CompanionAtlasID.allCases.map { SKTextureAtlas(named: $0.rawValue) }
        SKTextureAtlas.preloadTextureAtlases(atlases) {
            // Cache already populated synchronously; preload warms GPU residency.
        }
    }

    func textures(for id: CompanionAtlasID) -> [SKTexture] {
        lock.lock()
        if let cached = texturesByAtlas[id], !cached.isEmpty {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var ordered = Self.loadTextures(for: id)

        // Prefer Working art over an empty atlas so Focus never shows a blank companion.
        if ordered.isEmpty, id != .working {
            ordered = textures(for: .working)
        }

        lock.lock()
        if !ordered.isEmpty {
            texturesByAtlas[id] = ordered
        }
        lock.unlock()
        return ordered
    }

    /// Load order: asset-catalog / compiled atlas → bundle `.atlas` folder → UIImage names.
    static func loadTextures(for id: CompanionAtlasID) -> [SKTexture] {
        let atlas = SKTextureAtlas(named: id.rawValue)
        let fromAtlas = orderedTextures(from: atlas)
        if fromAtlas.count >= id.expectedFrameCount {
            return fromAtlas
        }
        if !fromAtlas.isEmpty {
            return fromAtlas
        }

        let fromBundle = bundlePNGTextures(atlasName: id.rawValue)
        if !fromBundle.isEmpty {
            return fromBundle
        }

        return uiImageTextures(prefix: id.framePrefix, count: id.expectedFrameCount)
    }

    /// Filename-sorted textures so `working_000` … `working_011` play in authoring order.
    static func orderedTextureNames(from atlas: SKTextureAtlas) -> [String] {
        sortedTextureNames(atlas.textureNames)
    }

    /// Pure sort used by atlases and unit tests — keeps zero-padded frames in authoring order.
    static func sortedTextureNames(_ names: [String]) -> [String] {
        names.sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    static func orderedTextures(from atlas: SKTextureAtlas) -> [SKTexture] {
        orderedTextureNames(from: atlas).compactMap { name -> SKTexture? in
            let texture = atlas.textureNamed(name)
            // Empty placeholder textures have zero size when the name is missing.
            guard texture.size().width > 1, texture.size().height > 1 else { return nil }
            texture.filteringMode = .linear
            texture.usesMipmaps = false
            return texture
        }
    }

    private static func bundlePNGTextures(atlasName: String) -> [SKTexture] {
        let subdirs = ["\(atlasName).atlas", "Atlases/\(atlasName).atlas", atlasName]
        for subdir in subdirs {
            guard let urls = Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: subdir),
                  !urls.isEmpty
            else { continue }
            let ordered = urls.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            let textures: [SKTexture] = ordered.compactMap { url in
                guard let image = UIImage(contentsOfFile: url.path) else { return nil }
                let texture = SKTexture(image: image)
                texture.filteringMode = .linear
                return texture
            }
            if !textures.isEmpty { return textures }
        }
        return []
    }

    private static func uiImageTextures(prefix: String, count: Int) -> [SKTexture] {
        (0..<count).compactMap { index in
            let name = String(format: "%@_%03d", prefix, index)
            guard let image = UIImage(named: name) else { return nil }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            return texture
        }
    }
}

/// Playback clip describing which atlas to use and how to run it.
struct CompanionAnimationClip: Equatable {
    enum Playback: Equatable {
        case loop
        case playOnceHoldLast
        case staticFrame
    }

    let atlas: CompanionAtlasID
    let playback: Playback
    /// Seconds per frame. Chosen so Working ≈ 2.6s and Deep Focus ≈ 3.5s over 12 frames.
    let timePerFrame: TimeInterval

    static func clip(for state: CompanionAnimationState, reduceMotion: Bool) -> CompanionAnimationClip {
        if reduceMotion {
            return CompanionAnimationClip(
                atlas: atlas(for: state),
                playback: .staticFrame,
                timePerFrame: 0
            )
        }

        switch state {
        case .working, .preparing:
            return CompanionAnimationClip(atlas: .typing, playback: .loop, timePerFrame: 0.075)
        case .deepFocus:
            return CompanionAnimationClip(atlas: .typing, playback: .loop, timePerFrame: 0.075)
        case .paused, .idle:
            return CompanionAnimationClip(atlas: .working, playback: .staticFrame, timePerFrame: 0)
        case .completed, .celebrating, .levelUp:
            return CompanionAnimationClip(atlas: .completed, playback: .playOnceHoldLast, timePerFrame: 1.7 / 12.0)
        case .timerExpired:
            return CompanionAnimationClip(atlas: .expired, playback: .playOnceHoldLast, timePerFrame: 1.5 / 12.0)
        }
    }

    private static func atlas(for state: CompanionAnimationState) -> CompanionAtlasID {
        switch state {
        case .working, .preparing, .paused, .idle:
            return .working
        case .deepFocus:
            return .deepFocus
        case .completed, .celebrating, .levelUp:
            return .completed
        case .timerExpired:
            return .expired
        }
    }

    /// Prefer a mid-loop pose for Reduce Motion so the desk scene reads clearly.
    func staticTexture(from textures: [SKTexture]) -> SKTexture? {
        guard !textures.isEmpty else { return nil }
        switch playback {
        case .playOnceHoldLast:
            return textures.last
        case .loop, .staticFrame:
            return textures[textures.count / 2]
        }
    }
}
