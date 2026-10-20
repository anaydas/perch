import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ShelfStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Background", selection: $settings.background) {
                    ForEach(IslandBackground.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Outline", selection: $settings.outline) {
                    ForEach(IslandOutline.allCases) { Text($0.label).tag($0) }
                }

                Picker("Outline color", selection: $settings.tint) {
                    ForEach(OutlineTint.allCases) { tint in
                        Text(tint.label).tag(tint)
                    }
                }
            }

            Section("Capture") {
                Toggle("Catch new screenshots automatically", isOn: $settings.autoCatchScreenshots)
                Toggle("Keep clipboard history in the Recent tab", isOn: $settings.clipboardHistory)
                Toggle("Blur text that looks like a password or API key", isOn: $settings.hideSensitive)
            }

            Section("Cleanup") {
                Picker("Remove unstarred items after", selection: $settings.expiryHours) {
                    Text("Never").tag(0)
                    Text("1 day").tag(24)
                    Text("3 days").tag(72)
                    Text("1 week").tag(168)
                }
                HStack {
                    Button("Clear Recent") { store.clearRecent() }
                    Button("Clear Shelf") { store.clearShelf() }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                LabeledContent("Keep island open", value: "⌥ Space")
                LabeledContent("Pin clipboard", value: "⌥ ⌘ V")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .onChange(of: settings.expiryHours) { _ in store.purgeExpired() }
    }
}
