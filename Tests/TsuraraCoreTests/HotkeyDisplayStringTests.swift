import Testing
import TsuraraCore

@Suite
struct HotkeyDisplayStringTests {
    @Test
    func displaysSingleModifierAndLetter() {
        #expect(
            hotkeyDisplayString(
                modifierFlags: HotkeyModifiers.nsCommand,
                keyCode: 0
            ) == "⌘A"
        )
    }

    @Test
    func displaysMultipleModifiersInStableOrder() {
        let flags = HotkeyModifiers.nsControl | HotkeyModifiers.nsShift
            | HotkeyModifiers.nsOption | HotkeyModifiers.nsCommand
        #expect(hotkeyDisplayString(modifierFlags: flags, keyCode: 49) == "⌃⌥⇧⌘Space")
    }

    @Test
    func displaysNamedNavigationAndFunctionKeys() {
        let flags = HotkeyModifiers.nsOption | HotkeyModifiers.nsShift
        #expect(hotkeyDisplayString(modifierFlags: flags, keyCode: 123) == "⌥⇧←")
        #expect(hotkeyDisplayString(modifierFlags: HotkeyModifiers.nsControl, keyCode: 122) == "⌃F1")
    }

    @Test
    func fallsBackForUnknownKeyCodeAndIgnoresUnrelatedFlags() {
        let unrelatedFlag = 1 << 23
        #expect(hotkeyDisplayString(modifierFlags: unrelatedFlag, keyCode: 999) == "Key 999")
    }
}
