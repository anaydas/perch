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

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // no Dock icon; lives in the notch + menu bar
        app.run()
    }
}
