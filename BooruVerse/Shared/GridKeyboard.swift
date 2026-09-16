import SwiftUI

#if canImport(AppKit)
import AppKit
#endif
#if canImport(GameController)
import GameController
#endif

/// ANSI / virtual key codes — layout-independent (physical key, not produced character).
enum HardwareKeyCode {
    static let a: UInt16 = 0x00
    static let f: UInt16 = 0x03
    static let `return`: UInt16 = 0x24
    static let escape: UInt16 = 0x35
    static let space: UInt16 = 0x31
    static let leftArrow: UInt16 = 0x7B
    static let rightArrow: UInt16 = 0x7C
    static let downArrow: UInt16 = 0x7D
    static let upArrow: UInt16 = 0x7E
}

enum GridKeyboardAction: Equatable {
    case move(Int) // delta index; up/down use column stride from caller
    case moveVertical(Int) // -1 up / +1 down
    case open
    case peek
    case favorite
    case clearSelection
    case selectVisible
}

enum GridKeyboard {
    /// Prefer hardware keyCode (Mac / iPad via GameController). Fallback: KeyEquivalent.
    static func action(for press: KeyPress) -> GridKeyboardAction? {
#if os(macOS)
        if let event = NSApp.currentEvent, event.type == .keyDown || event.type == .flagsChanged {
            if let action = action(keyCode: event.keyCode, modifiers: press.modifiers) {
                return action
            }
        }
#endif
#if canImport(GameController)
        if let action = actionFromGameController(modifiers: press.modifiers) {
            return action
        }
#endif
        return action(keyEquivalent: press.key, modifiers: press.modifiers)
    }

    static func action(keyCode: UInt16, modifiers: EventModifiers) -> GridKeyboardAction? {
        switch keyCode {
        case HardwareKeyCode.leftArrow:
            return .move(-1)
        case HardwareKeyCode.rightArrow:
            return .move(1)
        case HardwareKeyCode.upArrow:
            return .moveVertical(-1)
        case HardwareKeyCode.downArrow:
            return .moveVertical(1)
        case HardwareKeyCode.return:
            return .open
        case HardwareKeyCode.space:
            return .peek
        case HardwareKeyCode.f:
            return .favorite
        case HardwareKeyCode.escape:
            return .clearSelection
        case HardwareKeyCode.a where modifiers.contains(.command):
            return .selectVisible
        default:
            return nil
        }
    }

#if canImport(GameController)
    /// Layout-independent F / ⌘A when `GCKeyboard` is available (iPad HW keyboard).
    private static func actionFromGameController(modifiers: EventModifiers) -> GridKeyboardAction? {
        guard let input = GCKeyboard.coalesced?.keyboardInput else { return nil }
        if input.button(forKeyCode: .keyF)?.isPressed == true {
            return .favorite
        }
        if modifiers.contains(.command),
           input.button(forKeyCode: .keyA)?.isPressed == true {
            return .selectVisible
        }
        return nil
    }
#endif

    /// Fallback when keyCode is unavailable. Arrows/Space/Return/Esc are layout-independent.
    static func action(keyEquivalent key: KeyEquivalent, modifiers: EventModifiers) -> GridKeyboardAction? {
        switch key {
        case .leftArrow: return .move(-1)
        case .rightArrow: return .move(1)
        case .upArrow: return .moveVertical(-1)
        case .downArrow: return .moveVertical(1)
        case .return: return .open
        case .space: return .peek
        case .escape: return .clearSelection
        default:
            break
        }
        if key == KeyEquivalent("f") || key == KeyEquivalent("F") {
            return .favorite
        }
        if modifiers.contains(.command), key == KeyEquivalent("a") || key == KeyEquivalent("A") {
            return .selectVisible
        }
        return nil
    }
}
