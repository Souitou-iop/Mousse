import Foundation

/// Contains an element's decode failure to that element instead of failing the whole array.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) { value = try? T(from: decoder) }
}

enum AutoScrollSpeedSetting {
    static let range = 0.25...8.0
    static let step = 0.05
}

enum AutoScrollClickDelaySetting {
    static let range = 0.05...0.50
    static let step = 0.01
    static let defaultValue = 0.20
}

enum PointerSpeedSetting {
    static let range = 0.25...4.0
    static let step = 0.05

    static func clamp(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

enum PointerAccelerationOverride: String, Codable, Sendable, CaseIterable, Equatable {
    case inherit
    case enabled
    case disabled
}

struct PointerAppProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var bundleID: String
    var acceleration: PointerAccelerationOverride = .inherit
    var speedMultiplier: Double?

    init(id: UUID = UUID(), bundleID: String,
         acceleration: PointerAccelerationOverride = .inherit,
         speedMultiplier: Double? = nil) {
        self.id = id
        self.bundleID = bundleID
        self.acceleration = acceleration
        self.speedMultiplier = speedMultiplier.map(PointerSpeedSetting.clamp)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleID = try c.decode(String.self, forKey: .bundleID)
        acceleration = (try? c.decodeIfPresent(PointerAccelerationOverride.self,
                                                forKey: .acceleration)) ?? .inherit
        if let value = (try? c.decodeIfPresent(Double.self, forKey: .speedMultiplier)) ?? nil,
           value.isFinite {
            speedMultiplier = PointerSpeedSetting.clamp(value)
        } else {
            speedMultiplier = nil
        }
    }
}

/// How the mouse wheel scrolls.
enum ScrollMode: String, Codable, Sendable, CaseIterable {
    case standard    // OS stepped wheel — raw passthrough; each notch jumps instantly
    case smooth      // trackpad-style eased momentum
    case smoothStep  // Windows-browser style: each notch eases a fixed N-line step, no coast

    var label: String {
        switch self {
        case .standard:   return Localized.text("scroll.mode.standard")
        case .smooth:     return Localized.text("scroll.mode.smooth")
        case .smoothStep: return Localized.text("scroll.mode.smoothStep")
        }
    }
}

/// How a physical mouse-button input triggers an action.
enum ButtonTrigger: String, Codable, Sendable, CaseIterable, Hashable {
    case click
    case doubleClick
    case hold

    var label: String {
        switch self {
        case .click:       return Localized.text("buttons.trigger.click")
        case .doubleClick: return Localized.text("buttons.trigger.doubleClick")
        case .hold:        return Localized.text("buttons.trigger.hold")
        }
    }
}

/// A single mouse-button → action mapping.
struct ButtonMapping: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var buttonNumber: Int   // 1-based: 1=left, 2=right, 3=middle, 4/5=side buttons, ...
    var trigger: ButtonTrigger
    var action: RemapAction

    init(id: UUID = UUID(), buttonNumber: Int, trigger: ButtonTrigger = .click,
         action: RemapAction) {
        self.id = id
        self.buttonNumber = buttonNumber
        self.trigger = trigger
        self.action = action
    }

    // `id` is a UI identity, not user data — regenerate it when absent (e.g. a hand-edited or
    // older config) instead of letting synthesized decoding throw the whole mapping away.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        buttonNumber = try c.decode(Int.self, forKey: .buttonNumber)
        trigger = (try? c.decodeIfPresent(ButtonTrigger.self, forKey: .trigger)) ?? .click
        action = try c.decode(RemapAction.self, forKey: .action)
    }
}

/// The whole persisted configuration. Plain Codable value stored as JSON — no keychain,
/// no license, survives rebuilds.
/// `Equatable` so `ConfigStore` can skip the save + engine reload when an assignment changes
/// nothing — see the guard in its `didSet`.
struct AppConfig: Codable, Sendable, Equatable {
    var language: AppLanguage = .system
    var enabled: Bool = true
    var reverseScroll: Bool = false
    var scrollMode: ScrollMode = .smooth
    var scrollSmoothness: ScrollSmoothness = .balanced // Smooth mode curve profile (derived)
    var scrollSpeed: Double = 0.5       // 0.05 (slowest) … 3.0 (fast); Smooth mode: sensitivity
                                        // anchors (0=low, 0.5=medium, 1=high); also scales hi-res gain
    var scrollLines: Int = 3            // lines per notch in Smooth-step mode (Windows default = 3)
    var scrollAcceleration: Bool = true // rapid consecutive notches scroll farther (Smooth mode only)
    var zoomSpeed: Double = 1.0         // Cmd+wheel pinch-zoom sensitivity, independent of scrollSpeed
    var edgeScroll: Bool = false        // pointer resting on the screen edge scrolls continuously
    var edgeScrollSpeed: Double = 400.0 // px/s while edge scrolling
    var autoScrollSpeed: Double = 1.5   // auto-scroll: additional scroll px/s per px of pointer offset
    var autoScrollBaseSpeed: Double = 120.0 // auto-scroll: px/s as soon as the pointer leaves the dead zone
    var autoScrollClickDelay: Double = AutoScrollClickDelaySetting.defaultValue
    var showAutoScrollHUD: Bool = true  // show the single-process anchor/direction overlay
    var smoothHighRes: Bool = false     // also smooth high-res "continuous" mice (e.g. Keychron M6) that
                                        // lack a flywheel; keep off for MX-Master-style free-spin mice
    var doubleClickInterval: Double = 0.26
    var holdDuration: Double = 0.50
    var spaceDragButton: Int = 0        // 0 = off; else button held to drag-switch Spaces
    var spaceDragThreshold: Double = 200 // pixels of horizontal drag per Space switch (discrete mode)
    var spaceDragReverse: Bool = false  // flip drag direction ↔ Space direction
    var spaceDragFollowFinger: Bool = true // drive the real Space-slide (trackpad-like) when the
                                           // OS supports it; off = discrete one-jump-per-distance
    var spaceDragLockPointer: Bool = true // anchor the pointer at the drag's origin while
                                          // dragging (MMF "lock pointer during drag")
    var excludedBundleIDs: [String] = [] // apps where every Mousse scroll transform is bypassed
    var verticalToHorizontalBundleIDs: [String] = [] // apps where the scroll axes are SWAPPED (the
                                         // wheel scrolls horizontally): purpose-built for
                                         // horizontal-first browsers like Nimble Commander's Brief
                                         // panels — smoothing stays on, we transpose ourselves
    var configuredButtons: [Int] = [4, 5] // persists empty button groups in the mapping editor
    var mappings: [ButtonMapping] = AppConfig.defaultMappings
    var pointerControlEnabled: Bool = false
    var pointerAccelerationEnabled: Bool = true
    var pointerSpeedMultiplier: Double = 1.0
    var pointerAppProfiles: [PointerAppProfile] = []

    /// Sensible defaults so the app is useful on first launch.
    static let defaultMappings: [ButtonMapping] = [
        ButtonMapping(buttonNumber: 4, action: .spaceLeft),
        ButtonMapping(buttonNumber: 5, action: .spaceRight),
    ]
}

/// Tolerant decoding: a missing key OR an unreadable value (type mismatch, unknown enum case —
/// e.g. a config written by a newer app version) falls back to that field's default instead of
/// throwing, so one bad value never wipes the whole saved config. Mappings degrade per element:
/// a broken mapping is dropped, the rest survive. Encoding stays synthesized.
extension AppConfig {
    enum CodingKeys: String, CodingKey {
        case language, enabled, reverseScroll, scrollMode, scrollSmoothness, smoothScroll, scrollSpeed, scrollLines
        case scrollAcceleration, smoothHighRes, zoomSpeed, doubleClickInterval, holdDuration
        case edgeScroll, edgeScrollSpeed, autoScrollSpeed, autoScrollBaseSpeed, autoScrollClickDelay
        case showAutoScrollHUD
        case spaceDragButton, spaceDragThreshold, spaceDragReverse, spaceDragFollowFinger, spaceDragLockPointer
        case excludedBundleIDs, verticalToHorizontalBundleIDs, configuredButtons, mappings
        case pointerControlEnabled, pointerAccelerationEnabled, pointerSpeedMultiplier
        case pointerAppProfiles
    }

    init(from decoder: Decoder) throws {        self.init()
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        // `try?` (not just decodeIfPresent) so a present-but-invalid value also falls back.
        func field<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(type, forKey: key)) ?? nil
        }
        language           = field(AppLanguage.self, .language)      ?? language
        enabled            = field(Bool.self,   .enabled)            ?? enabled
        reverseScroll      = field(Bool.self,   .reverseScroll)      ?? reverseScroll
        // Prefer scrollMode; fall back to the legacy `smoothScroll` bool if that's all we have.
        if let mode = field(ScrollMode.self, .scrollMode) {
            scrollMode = mode
        } else if let legacy = field(Bool.self, .smoothScroll) {
            scrollMode = legacy ? .smooth : .standard
        }
        scrollSmoothness   = field(ScrollSmoothness.self, .scrollSmoothness) ?? scrollSmoothness
        scrollSpeed        = field(Double.self, .scrollSpeed)        ?? scrollSpeed
        scrollLines        = field(Int.self,    .scrollLines)        ?? scrollLines
        scrollAcceleration = field(Bool.self,   .scrollAcceleration) ?? scrollAcceleration
        zoomSpeed          = field(Double.self, .zoomSpeed)          ?? zoomSpeed
        edgeScroll         = field(Bool.self,   .edgeScroll)         ?? edgeScroll
        edgeScrollSpeed    = field(Double.self, .edgeScrollSpeed)    ?? edgeScrollSpeed
        autoScrollSpeed    = field(Double.self, .autoScrollSpeed)    ?? autoScrollSpeed
        autoScrollBaseSpeed = field(Double.self, .autoScrollBaseSpeed) ?? autoScrollBaseSpeed
        if let value = field(Double.self, .autoScrollClickDelay), value.isFinite {
            autoScrollClickDelay = min(max(value, AutoScrollClickDelaySetting.range.lowerBound),
                                       AutoScrollClickDelaySetting.range.upperBound)
        }
        showAutoScrollHUD   = field(Bool.self, .showAutoScrollHUD)    ?? showAutoScrollHUD
        smoothHighRes      = field(Bool.self,   .smoothHighRes)      ?? smoothHighRes
        if let value = field(Double.self, .doubleClickInterval), value.isFinite {
            doubleClickInterval = min(max(value, 0.10), 0.50)
        }
        if let value = field(Double.self, .holdDuration), value.isFinite {
            holdDuration = min(max(value, 0.10), 0.80)
        }
        spaceDragButton    = field(Int.self,    .spaceDragButton)    ?? spaceDragButton
        spaceDragThreshold = field(Double.self, .spaceDragThreshold) ?? spaceDragThreshold
        spaceDragReverse   = field(Bool.self,   .spaceDragReverse)   ?? spaceDragReverse
        spaceDragFollowFinger = field(Bool.self, .spaceDragFollowFinger) ?? spaceDragFollowFinger
        spaceDragLockPointer   = field(Bool.self, .spaceDragLockPointer)   ?? spaceDragLockPointer
        excludedBundleIDs  = field([String].self, .excludedBundleIDs) ?? excludedBundleIDs
        verticalToHorizontalBundleIDs = field([String].self, .verticalToHorizontalBundleIDs) ?? verticalToHorizontalBundleIDs
        if c.contains(.mappings) {
            if let decodedMappings = field([Lossy<ButtonMapping>].self, .mappings) {
                mappings = decodedMappings.compactMap(\.value)
            }
        }
        pointerControlEnabled = field(Bool.self, .pointerControlEnabled) ?? pointerControlEnabled
        pointerAccelerationEnabled = field(Bool.self, .pointerAccelerationEnabled)
            ?? pointerAccelerationEnabled
        if let value = field(Double.self, .pointerSpeedMultiplier), value.isFinite {
            pointerSpeedMultiplier = PointerSpeedSetting.clamp(value)
        }
        if c.contains(.pointerAppProfiles),
           let decodedProfiles = field([Lossy<PointerAppProfile>].self, .pointerAppProfiles) {
            pointerAppProfiles = decodedProfiles.compactMap(\.value)
        }
        let savedButtons = field([Int].self, .configuredButtons) ?? []
        configuredButtons = Array(Set((savedButtons + mappings.map(\.buttonNumber)).filter { $0 >= 3 })).sorted()

        scrollSpeed        = min(max(scrollSpeed, 0.05), 3.0)
        zoomSpeed          = min(max(zoomSpeed, 0.2), 6.0)
        edgeScrollSpeed    = min(max(edgeScrollSpeed, 50), 2400)
        autoScrollSpeed    = min(max(autoScrollSpeed, AutoScrollSpeedSetting.range.lowerBound),
                                 AutoScrollSpeedSetting.range.upperBound)
        autoScrollBaseSpeed = min(max(autoScrollBaseSpeed, 0), 1000)
        scrollLines        = min(max(scrollLines, 1), 10)
        spaceDragThreshold = min(max(spaceDragThreshold, 100), 400)
    }

    // Custom encode because `smoothScroll` is a decode-only legacy key with no backing property.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(language, forKey: .language)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(reverseScroll, forKey: .reverseScroll)
        try c.encode(scrollMode, forKey: .scrollMode)
        try c.encode(scrollSmoothness, forKey: .scrollSmoothness)
        try c.encode(scrollSpeed, forKey: .scrollSpeed)
        try c.encode(scrollLines, forKey: .scrollLines)
        try c.encode(scrollAcceleration, forKey: .scrollAcceleration)
        try c.encode(zoomSpeed, forKey: .zoomSpeed)
        try c.encode(edgeScroll, forKey: .edgeScroll)
        try c.encode(edgeScrollSpeed, forKey: .edgeScrollSpeed)
        try c.encode(autoScrollSpeed, forKey: .autoScrollSpeed)
        try c.encode(autoScrollBaseSpeed, forKey: .autoScrollBaseSpeed)
        try c.encode(autoScrollClickDelay, forKey: .autoScrollClickDelay)
        try c.encode(showAutoScrollHUD, forKey: .showAutoScrollHUD)
        try c.encode(smoothHighRes, forKey: .smoothHighRes)
        try c.encode(doubleClickInterval, forKey: .doubleClickInterval)
        try c.encode(holdDuration, forKey: .holdDuration)
        try c.encode(spaceDragButton, forKey: .spaceDragButton)
        try c.encode(spaceDragThreshold, forKey: .spaceDragThreshold)
        try c.encode(spaceDragReverse, forKey: .spaceDragReverse)
        try c.encode(spaceDragFollowFinger, forKey: .spaceDragFollowFinger)
        try c.encode(spaceDragLockPointer, forKey: .spaceDragLockPointer)
        try c.encode(excludedBundleIDs, forKey: .excludedBundleIDs)
        try c.encode(verticalToHorizontalBundleIDs, forKey: .verticalToHorizontalBundleIDs)
        try c.encode(configuredButtons, forKey: .configuredButtons)
        try c.encode(mappings, forKey: .mappings)
        try c.encode(pointerControlEnabled, forKey: .pointerControlEnabled)
        try c.encode(pointerAccelerationEnabled, forKey: .pointerAccelerationEnabled)
        try c.encode(pointerSpeedMultiplier, forKey: .pointerSpeedMultiplier)
        try c.encode(pointerAppProfiles, forKey: .pointerAppProfiles)
    }
}
