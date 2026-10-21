import AppKit

@main
enum PerchMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // no Dock icon; lives in the notch + menu bar
        app.run()
    }
}
