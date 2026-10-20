import AppKit

@main
enum NotchShelfMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // no Dock icon; lives in the notch + menu bar
        app.run()
    }
}
