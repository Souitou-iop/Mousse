import Foundation
import Combine

/// Loads/saves `AppConfig` as JSON in Application Support and pushes changes to the engine.
/// `@MainActor` so SwiftUI can bind to it directly.
@MainActor
final class ConfigStore: ObservableObject {

    static let shared = ConfigStore()

    @Published var config: AppConfig {
        didSet {
            // `didSet` fires on every assignment, including one that changes nothing — and SwiftUI
            // bindings write identical values constantly (a slider re-asserting its current step,
            // MenuBarExtra re-asserting its insertion state). Without this guard each of those
            // costs a disk write plus a full engine reload, and any binding whose write is itself
            // triggered by the resulting republish spins into a feedback loop.
            guard config != oldValue else { return }
            // Engine first and unconditionally — this is the change the user feels. Only the disk
            // write is deferred: dragging one slider walks ~30 distinct values, and each atomic
            // write (encode, temp file, rename) is main-thread I/O nobody needs mid-drag.
            EventTapEngine.shared.reload(config)
            scheduleSave()
        }
    }

    private let fileURL: URL

    /// Non-nil exactly while a change is written-pending — `flushPendingSave()` keys off that.
    private var saveTask: Task<Void, Never>?

    private init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Mousse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")

        // One-time migration: the app was called SilkMouse (and QmouseFix before that) — adopt
        // the newest prior config so a rename doesn't silently reset anyone's settings.
        // (Copy, not move: harmless leftover.)
        if !FileManager.default.fileExists(atPath: fileURL.path),
           let legacy = ["SilkMouse/config.json", "QmouseFix/config.json"]
               .map({ support.appendingPathComponent($0) })
               .first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            try? FileManager.default.copyItem(at: legacy, to: fileURL)
        }

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = loaded
        } else {
            config = AppConfig()
        }
    }

    /// Coalesce a burst of changes into a single write, half a second after it settles.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            self.save()
        }
    }

    /// Write a still-pending change out now. Called on quit: a setting the user changed in the last
    /// half second must not die with the process.
    func flushPendingSave() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
