import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ShelfStore
    var onShowShortcuts: () -> Void = {}
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            NSLog("Perch: Launch at login \(enabled ? "register" : "unregister") failed: \(error)")
        }
        loginStatus = SMAppService.mainApp.status
    }

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

                Toggle("Hide while a full-screen video plays", isOn: $settings.hideInFullScreen)

                if settings.style == .floating || settings.style == .orb {
                    Button("Reset position") { settings.floatingCenter = nil }
                        .disabled(settings.floatingCenter == nil)
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(IslandTheme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Background", selection: $settings.background) {
                    ForEach(IslandBackground.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Outline", selection: $settings.outline) {
                    ForEach(IslandOutline.allCases) { Text($0.label).tag($0) }
                }

                Picker("Accent color", selection: $settings.tint) {
                    ForEach(OutlineTint.allCases) { tint in
                        Text(tint.label).tag(tint)
                    }
                }
            }

            Section("Shelf") {
                Toggle("Show filter tabs (All, Images, Text, Files, Recent)", isOn: $settings.showFilters)
                Toggle("Play a sound when an item lands", isOn: $settings.soundOnItemAdded)
                    .onChange(of: settings.soundOnItemAdded) { on in if on { Sounds.play(.itemAdded) } }
            }

            Section("Capture") {
                Toggle("Catch new screenshots automatically", isOn: $settings.autoCatchScreenshots)
                Toggle("Catch new screen recordings automatically", isOn: $settings.autoCatchRecordings)
                Toggle("Add everything you copy to the shelf", isOn: $settings.clipboardHistory)
                Text(settings.clipboardHistory
                     ? "Copied text, images and files land on the shelf (and in the Recent tab)."
                     : "Off: copies stay off the shelf. Add something on purpose with ⌥⌘V, a drop, or right-click → Services → Add to Perch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Blur text that looks like a password or API key", isOn: $settings.hideSensitive)
            }

            Section("Claude Code") {
                Toggle("Show Claude", isOn: $settings.showClaude)
                Group {
                    Toggle("Running Claude Code sessions", isOn: $settings.showClaudeSessions)
                    Toggle("Plan usage (5-hour and weekly limits)", isOn: $settings.showClaudeUsage)
                    Toggle("Play a sound when a session needs you or finishes", isOn: $settings.soundOnClaude)
                        .onChange(of: settings.soundOnClaude) { on in if on { Sounds.play(.claudeNeedsYou) } }
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
                Toggle("Launch at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { setLaunchAtLogin($0) }
                ))
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("macOS needs you to allow Perch in Login Items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginError {
                    Text("Couldn't change Launch at login: \(loginError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                LabeledContent("Keyboard shortcuts") {
                    Button("Show All Shortcuts…", action: onShowShortcuts)
                }
                Text("⌥⌘F search · ⌥⌘V pin clipboard · ⌥Space keep open · ? in the shelf shows them all")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 760)
        .onChange(of: settings.expiryHours) { _ in store.purgeExpired() }
        // The window is reused, and the login item can change in System Settings: re-check when it comes forward.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }
}
