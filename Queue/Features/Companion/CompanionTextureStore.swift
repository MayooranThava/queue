import SpriteKit

/// Atlas identifiers matching `Queue/Resources/Atlases/*.atlas`.
enum CompanionAtlasID: String, CaseIterable, Sendable {
    case working = "Working"
    case deepFocus = "DeepFocus"
    case completed = "Completed"
    case expired = "Expired"
}

/// Loads and preloads companion sprite atlases once. Texture order follows filename sort.
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

        // Always ensure the cache is warm — cheap if already filled.
        for id in CompanionAtlasID.allCases {
            _ = textures(for: id)
        }

        guard !already else { return }
        let atlases = CompanionAtlasID.allCases.map { SKTextureAtlas(named: $0.rawValue) }
        SKTextureAtlas.preload(atlases) {
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

        let atlas = SKTextureAtlas(named: id.rawValue)
        var ordered = Self.orderedTextures(from: atlas)

        // Until DeepFocus / Completed / Expired art is dropped into Resources/Atlases,
        // fall back to Working so transitions stay pixel-aligned with the supplied set.
        if ordered.isEmpty, id != .working {
            ordered = textures(for: .working)
        }

        lock.lock()
        texturesByAtlas[id] = ordered
        lock.unlock()
        return ordered
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
        orderedTextureNames(from: atlas).map { name in
            let texture = atlas.textureNamed(name)
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
            return CompanionAnimationClip(atlas: .working, playback: .loop, timePerFrame: 2.6 / 12.0)
        case .deepFocus:
            return CompanionAnimationClip(atlas: .deepFocus, playback: .loop, timePerFrame: 3.5 / 12.0)
        case .paused, .idle:
            // Calm static pose from Working — no typing loop while paused/idle.
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
