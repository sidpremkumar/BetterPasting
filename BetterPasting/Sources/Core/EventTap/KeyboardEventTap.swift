import CoreGraphics
import Carbon.HIToolbox
import Combine

enum ShortcutEvent {
    case togglePanel       // CMD+SHIFT+V
    case quickCopy(Int)    // CMD+1-0 (0-9)
    case navigateUp
    case navigateDown
    case confirm           // Enter - confirm search
    case selectCurrent     // Right arrow - copy current item to clipboard
    case quickLook         // Space - preview current item
    case dismiss           // Escape
    case forceHidePanel    // CMD+Tab - always close panel immediately
    case commandStateChanged(Bool)  // CMD pressed/released
    case activateSearch    // Enter when search not active
    case typeToSearch(String) // User typed a character to start searching
}

final class KeyboardEventTap {
    let onShortcutTriggered = PassthroughSubject<ShortcutEvent, Never>()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let modifierTracker = ModifierKeyTracker()
    private var previousFlags: CGEventFlags = []
    private var panelVisible = false
    private var searchActive = false

    init() {
        setupEventTap()
    }

    deinit {
        disable()
    }

    func disable() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        print("[KeyboardEventTap] Disabled")
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if !visible {
            searchActive = false
        }
    }

    func setSearchActive(_ active: Bool) {
        searchActive = active
    }

    private func setupEventTap() {
        let eventMask: CGEventMask = (
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo = userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let eventTap = Unmanaged<KeyboardEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return eventTap.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            print("[KeyboardEventTap] Failed to create event tap. Check Input Monitoring permission.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[KeyboardEventTap] Successfully created and enabled")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled events
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                print("[KeyboardEventTap] Re-enabled after being disabled")
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Handle modifier changes
        if type == .flagsChanged {
            let wasCommandPressed = previousFlags.contains(.maskCommand)
            previousFlags = flags
            modifierTracker.update(flags: flags)

            // Notify about CMD key state changes when panel is visible
            if panelVisible {
                let isCommandPressed = flags.contains(.maskCommand)
                if wasCommandPressed != isCommandPressed {
                    onShortcutTriggered.send(.commandStateChanged(isCommandPressed))
                }
            }

            return Unmanaged.passUnretained(event)
        }

        // Only handle key down events
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        // CMD+SHIFT+V to toggle panel
        if keyCode == UInt16(kVK_ANSI_V) &&
           modifierTracker.isCommandPressed &&
           modifierTracker.isShiftPressed {
            print("[KeyboardEventTap] Toggle panel (CMD+SHIFT+V)")
            onShortcutTriggered.send(.togglePanel)
            return nil  // Consume event
        }

        // When panel is visible, handle additional shortcuts
        if panelVisible {
            // CMD+Tab - close sidebar and let the event pass through to system/BetterTabbing
            if keyCode == UInt16(kVK_Tab) && modifierTracker.isCommandPressed && !modifierTracker.isShiftPressed {
                print("[KeyboardEventTap] CMD+Tab detected, force hiding sidebar")
                onShortcutTriggered.send(.forceHidePanel)
                // Don't consume the event - let it pass through to the system
                return Unmanaged.passUnretained(event)
            }

            // CMD+Shift+Tab - also close sidebar for reverse app switching
            if keyCode == UInt16(kVK_Tab) && modifierTracker.isCommandPressed && modifierTracker.isShiftPressed {
                print("[KeyboardEventTap] CMD+Shift+Tab detected, force hiding sidebar")
                onShortcutTriggered.send(.forceHidePanel)
                return Unmanaged.passUnretained(event)
            }

            // Quick copy: CMD+1-0
            if modifierTracker.isCommandPressed && !modifierTracker.isShiftPressed {
                if let index = keyCodeToQuickCopyIndex(keyCode) {
                    print("[KeyboardEventTap] Quick copy CMD+\(index == 9 ? 0 : index + 1)")
                    onShortcutTriggered.send(.quickCopy(index))
                    return nil
                }
            }

            // Arrow keys for navigation
            if keyCode == UInt16(kVK_UpArrow) {
                print("[KeyboardEventTap] Navigate up")
                onShortcutTriggered.send(.navigateUp)
                return nil
            }

            if keyCode == UInt16(kVK_DownArrow) {
                print("[KeyboardEventTap] Navigate down")
                onShortcutTriggered.send(.navigateDown)
                return nil
            }

            // Left arrow to select/copy the current item
            if keyCode == UInt16(kVK_LeftArrow) {
                print("[KeyboardEventTap] Select/Copy (Left Arrow)")
                onShortcutTriggered.send(.selectCurrent)
                return nil
            }

            // Space for Quick Look preview
            if keyCode == UInt16(kVK_Space) && !searchActive {
                print("[KeyboardEventTap] Quick Look (Space)")
                onShortcutTriggered.send(.quickLook)
                return nil
            }

            // Tab for navigation (Tab = down, Shift+Tab = up)
            if keyCode == UInt16(kVK_Tab) {
                if modifierTracker.isShiftPressed {
                    print("[KeyboardEventTap] Navigate up (Shift+Tab)")
                    onShortcutTriggered.send(.navigateUp)
                } else {
                    print("[KeyboardEventTap] Navigate down (Tab)")
                    onShortcutTriggered.send(.navigateDown)
                }
                return nil
            }

            // Enter - activate search if not active, otherwise confirm
            if keyCode == UInt16(kVK_Return) {
                if searchActive {
                    print("[KeyboardEventTap] Confirm (Enter)")
                    onShortcutTriggered.send(.confirm)
                } else {
                    print("[KeyboardEventTap] Activate search (Enter)")
                    onShortcutTriggered.send(.activateSearch)
                }
                return nil
            }

            // Escape to dismiss (or deactivate search first)
            if keyCode == UInt16(kVK_Escape) {
                print("[KeyboardEventTap] Dismiss (Escape)")
                onShortcutTriggered.send(.dismiss)
                return nil
            }

            // Type-to-search: any printable character when search is not active
            if !searchActive && !modifierTracker.isCommandPressed && isPrintableKeyCode(keyCode) {
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
                if length > 0 {
                    let typed = String(utf16CodeUnits: chars, count: length)
                    let printable = typed.filter { !$0.isNewline }
                    if !printable.isEmpty {
                        print("[KeyboardEventTap] Type-to-search: '\(printable)'")
                        onShortcutTriggered.send(.typeToSearch(printable))
                        return nil
                    }
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    /// Check if a key code corresponds to a printable character (not a modifier/function key)
    private func isPrintableKeyCode(_ keyCode: UInt16) -> Bool {
        // Exclude function keys, modifiers, arrows, etc.
        let nonPrintable: Set<UInt16> = [
            UInt16(kVK_Return), UInt16(kVK_Tab), UInt16(kVK_Delete), UInt16(kVK_Escape),
            UInt16(kVK_ForwardDelete),
            UInt16(kVK_UpArrow), UInt16(kVK_DownArrow), UInt16(kVK_LeftArrow), UInt16(kVK_RightArrow),
            UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3), UInt16(kVK_F4),
            UInt16(kVK_F5), UInt16(kVK_F6), UInt16(kVK_F7), UInt16(kVK_F8),
            UInt16(kVK_F9), UInt16(kVK_F10), UInt16(kVK_F11), UInt16(kVK_F12),
            UInt16(kVK_Home), UInt16(kVK_End), UInt16(kVK_PageUp), UInt16(kVK_PageDown),
        ]
        return !nonPrintable.contains(keyCode)
    }

    private func keyCodeToQuickCopyIndex(_ keyCode: UInt16) -> Int? {
        // Map key codes to indices 0-9
        switch keyCode {
        case UInt16(kVK_ANSI_1): return 0
        case UInt16(kVK_ANSI_2): return 1
        case UInt16(kVK_ANSI_3): return 2
        case UInt16(kVK_ANSI_4): return 3
        case UInt16(kVK_ANSI_5): return 4
        case UInt16(kVK_ANSI_6): return 5
        case UInt16(kVK_ANSI_7): return 6
        case UInt16(kVK_ANSI_8): return 7
        case UInt16(kVK_ANSI_9): return 8
        case UInt16(kVK_ANSI_0): return 9
        default: return nil
        }
    }
}
