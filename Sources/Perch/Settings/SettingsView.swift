import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ShelfStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var placementNote: String {
        switch settings.style {
        case .notch: return "Joined to the screen edge. At the top of a MacBook with a notch, it wraps around the camera."
        case .floating: return "A capsule you can drag anywhere on the screen (drag the open shelf by its header). Position sets its starting spot and layout."
        case .orb: return "A circle with the item count that you can drag anywhere on the screen (drag the open shelf by its header). Position sets its starting spot and layout."
        }
    }

    var body: some View {
        Form {
            Section("Placement") {
                Picker("Position", selection: $settings.position) {
                    ForEach(IslandPosition.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Style", selection: $settings.style) {
                    ForEach(IslandStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Text(placementNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.style == .floating || settings.style == .orb {
                    Button("Reset position") { settings.floatingCenter = nil }
                        .disabled(settings.floatingCenter == nil)
                }
            }

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

            Section("Shelf") {
                Toggle("Show filter tabs (All, Images, Text, Files, Recent)", isOn: $settings.showFilters)
            }

            Section("Capture") {
                Toggle("Catch new screenshots automatically", isOn: $settings.autoCatchScreenshots)
                Toggle("Keep clipboard history in the Recent tab", isOn: $settings.clipboardHistory)
                Toggle("Blur text that looks like a password or API key", isOn: $settings.hideSensitive)
            }

            Section("Claude Code") {
                Toggle("Show Claude", isOn: $settings.showClaude)
                Group {
                    Toggle("Running Claude Code sessions", isOn: $settings.showClaudeSessions)
                    Toggle("Plan usage (5-hour and weekly limits)", isOn: $settings.showClaudeUsage)
                }
                .disabled(!settings.showClaude)
                .padding(.leading, 16)
                Text("Click the Claude logo at the top right of the shelf to see your sessions and usage; the ring around it shows 5-hour usage. Click a session to open it in the Claude app or jump to its terminal tab. Usage updates while a Claude Code session runs, through its status line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .frame(width: 480, height: 760)
        .onChange(of: settings.expiryHours) { _ in store.purgeExpired() }
    }
}
