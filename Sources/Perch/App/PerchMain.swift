import AppKit
import ServiceManagement

@main
enum PerchMain {
    @MainActor
    static func main() {
        // Used by scripts/uninstall.sh: only the app itself can remove its login item.
        if CommandLine.arguments.contains("--unregister-login-item") {
            try? SMAppService.mainApp.unregister()
            exit(0)
        }

        // Used to make the README screenshots: draws the island with sample data, then quits.
        if let flag = CommandLine.arguments.firstIndex(of: "--render-screenshots") {
            let args = CommandLine.arguments
            let folder = args.indices.contains(flag + 1) ? args[flag + 1] : "docs/screenshots"
            _ = NSApplication.shared
            let theme = args.firstIndex(of: "--theme").flatMap { args.indices.contains($0 + 1) ? IslandTheme(rawValue: args[$0 + 1]) : nil }
            ReadmeScreenshots.render(to: URL(fileURLWithPath: folder), theme: theme ?? .dark)
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // no Dock icon; lives in the notch + menu bar
        app.run()
    }
}
