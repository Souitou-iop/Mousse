import Foundation

struct ScrollDeviceSettings: Codable, Sendable, Equatable {
    var reverseScroll = false
    var reverseScrollHorizontal = false
    var scrollMode: ScrollMode = .smooth
    var scrollSmoothness: ScrollSmoothness = .balanced
    var scrollSpeed = 0.5
    var scrollLines = 3
    var scrollAcceleration = true
    var smoothHighRes = false
    var zoomSpeed = 1.0

    enum CodingKeys: String, CodingKey {
        case reverseScroll, reverseScrollHorizontal, scrollMode, scrollSmoothness, scrollSpeed
        case scrollLines, scrollAcceleration, smoothHighRes, zoomSpeed
    }

    init() {}

    /// Tolerant like `AppConfig`: a missing or unreadable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func field<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(type, forKey: key)) ?? nil
        }
        reverseScroll      = field(Bool.self, .reverseScroll) ?? reverseScroll
        reverseScrollHorizontal = field(Bool.self, .reverseScrollHorizontal) ?? reverseScroll
        scrollMode         = field(ScrollMode.self, .scrollMode) ?? scrollMode
        scrollSmoothness   = field(ScrollSmoothness.self, .scrollSmoothness) ?? scrollSmoothness
        scrollSpeed        = field(Double.self, .scrollSpeed) ?? scrollSpeed
        scrollLines        = field(Int.self, .scrollLines) ?? scrollLines
        scrollAcceleration = field(Bool.self, .scrollAcceleration) ?? scrollAcceleration
        smoothHighRes      = field(Bool.self, .smoothHighRes) ?? smoothHighRes
        zoomSpeed          = field(Double.self, .zoomSpeed) ?? zoomSpeed
        clampToUIRanges()
    }

    /// Same bounds the Settings UI enforces (see `AppConfig.init(from:)`).
    mutating func clampToUIRanges() {
        scrollSpeed = scrollSpeed.isFinite ? min(max(scrollSpeed, 0.05), 3.0) : 0.5
        scrollLines = min(max(scrollLines, 1), 10)
        zoomSpeed   = zoomSpeed.isFinite ? min(max(zoomSpeed, 0.2), 6.0) : 1.0
    }
}

/// Per-device scroll override, keyed by the mouse's USB/Bluetooth vendor + product ID — stable
/// across reconnects and ports (two identical mice share one profile).
struct DeviceProfile: Codable, Sendable, Equatable, Identifiable {
    var id: String      // `HIDDeviceInfo.key(vendorID:productID:)`
    var name: String    // product name at the time the profile was created (display only)
    var settings: ScrollDeviceSettings
}
