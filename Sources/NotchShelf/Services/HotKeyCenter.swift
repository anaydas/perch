import Carbon.HIToolbox

/// Global keyboard shortcuts via Carbon (no Accessibility permission needed).
final class HotKeyCenter {
    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { center.handlers[hotKeyID.id]?() }
            return noErr
        }, 1, &spec, selfPointer, &eventHandler)
    }

    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        handlers[id] = action
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E53_484C), id: id) // "NSHL"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            NSLog("NotchShelf: could not register hot key \(keyCode) (status \(status)); another app may be using it.")
        }
        hotKeyRefs.append(ref)
    }

    deinit {
        hotKeyRefs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
