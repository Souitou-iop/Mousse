import SwiftUI

struct DevicesView: View {
    @EnvironmentObject var store: ConfigStore
    @ObservedObject private var tracker: DeviceTracker

    init(tracker: DeviceTracker = .shared) { _tracker = ObservedObject(wrappedValue: tracker) }

    var body: some View {
        Form {
            if !store.config.enabled {
                Text(Localized.text("devices.disabled")).foregroundStyle(.secondary)
            }
            if !tracker.inputMonitoringGranted {
                Label(Localized.text("devices.permission"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button(Localized.text("general.grant")) {
                    _ = InputMonitoringPermission.request()
                    InputMonitoringPermission.openSettings()
                    tracker.retryIfNeeded()
                }
            }
            Section(Localized.text("devices.connected")) {
                if tracker.connected.isEmpty { Text(Localized.text("devices.empty")).foregroundStyle(.secondary) }
                ForEach(tracker.connected) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text(device.key).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !store.config.deviceProfiles.contains(where: { $0.id == device.key }) {
                            Button(Localized.text("devices.create")) {
                                guard !store.config.deviceProfiles.contains(where: { $0.id == device.key }) else { return }
                                store.config.deviceProfiles.append(DeviceProfile(id: device.key, name: device.name,
                                                                                settings: store.config.scrollSettings))
                            }
                        }
                    }
                }
            }
            ForEach(store.config.deviceProfiles) { profile in
                Section {
                    HStack {
                        Text(profile.name)
                        Spacer()
                        Text(Localized.text(tracker.connected.contains { $0.key == profile.id }
                                            ? "devices.connected" : "devices.offline"))
                            .font(.caption).foregroundStyle(.secondary)
                        Button(Localized.text("apps.remove")) {
                            store.config.deviceProfiles.removeAll { $0.id == profile.id }
                        }
                    }
                    Text(profile.id).font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup(Localized.text("devices.custom")) {
                        ScrollSettingsEditor(settings: settings(for: profile.id))
                    }
                }
            }
            Text(Localized.text("devices.description")).font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func settings(for key: String) -> Binding<ScrollDeviceSettings> {
        Binding(get: { store.config.deviceProfiles.first { $0.id == key }?.settings ?? store.config.scrollSettings },
                set: { value in
                    guard let index = store.config.deviceProfiles.firstIndex(where: { $0.id == key }) else { return }
                    var settings = value
                    settings.clampToUIRanges()
                    store.config.deviceProfiles[index].settings = settings
                })
    }
}

/// Device-only editor: leave the existing global page's enhanced controls and layout intact.
struct ScrollSettingsEditor: View {
    @Binding var settings: ScrollDeviceSettings
    var body: some View {
        Picker(Localized.text("scroll.style"), selection: $settings.scrollMode) {
            ForEach(ScrollMode.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        if settings.scrollMode.supportsSmoothness {
            Picker(Localized.text("scroll.smoothness"), selection: $settings.scrollSmoothness) {
                ForEach(ScrollSmoothness.allCases, id: \.self) { Text($0.label).tag($0) }
            }
        }
        Toggle(Localized.text("scroll.reverseVertical"), isOn: $settings.reverseScroll)
        Toggle(Localized.text("scroll.reverseHorizontal"), isOn: $settings.reverseScrollHorizontal)
        if settings.scrollMode.supportsWheelSpeed {
            ScrollSpeedControl(speed: $settings.scrollSpeed, mode: settings.scrollMode)
        }
        if settings.scrollMode.supportsLinesPerNotch {
            Stepper(value: $settings.scrollLines, in: 1...10) {
                Text(Localized.format("scroll.linesPerNotch", settings.scrollLines))
            }
        }
        if settings.scrollMode.supportsAcceleration {
            Toggle(Localized.text("scroll.acceleration"), isOn: $settings.scrollAcceleration)
        }
        if settings.scrollMode.supportsHighResSmoothing {
            Toggle(Localized.text("scroll.smoothHighRes"), isOn: $settings.smoothHighRes)
        }
        if settings.scrollMode.supportsWheelZoom {
            Text(Localized.format("scroll.zoomSpeedValue", settings.zoomSpeed))
            Slider(value: $settings.zoomSpeed, in: 0.2...6.0, step: 0.1)
        } else {
            Text(Localized.text("scroll.nativeDescription")).font(.caption).foregroundStyle(.secondary)
        }
    }
}


struct ScrollSpeedControl: View {
    @Binding var speed: Double
    let mode: ScrollMode
    var body: some View {
        VStack(alignment: .leading) {
            Text(Localized.format("scroll.speedValue", speed))
            Slider(value: $speed, in: 0.05...3.0, step: 0.05) {
                Text(Localized.text("scroll.speed"))
            } minimumValueLabel: { Text(Localized.text("scroll.slow")).font(.caption) }
              maximumValueLabel: { Text(Localized.text("scroll.fast")).font(.caption) }
            if let key = mode.wheelSpeedNoteKey {
                Text(Localized.text(key)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
