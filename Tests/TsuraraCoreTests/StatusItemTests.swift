import Testing
import TsuraraCore

@Test
@MainActor
func lengthChangeIsRecorded() {
    let statusItem = MockStatusItem()

    statusItem.length = 24
    statusItem.length = 32

    #expect(statusItem.lengthHistory == [24, 32])
}

@Test
@MainActor
func clickCallbackFires() {
    let statusItem = MockStatusItem()
    var clickWasObserved = false
    statusItem.onClick = { clickWasObserved = true }

    statusItem.fireClick()

    #expect(clickWasObserved)
}

@Test
@MainActor
func iconSymbolNameIsRecorded() {
    let statusItem = MockStatusItem()

    statusItem.setIcon(symbolName: "snowflake", accessibilityDescription: "Tsurara")

    #expect(statusItem.icons == [
        MockStatusItem.Icon(symbolName: "snowflake", accessibilityDescription: "Tsurara")
    ])
}

@Test
@MainActor
func visibilityChangesAreRecorded() {
    let statusItem = MockStatusItem(isVisible: true)

    statusItem.isVisible = false
    statusItem.isVisible = true

    #expect(statusItem.isVisibleHistory == [false, true])
    #expect(statusItem.isVisible)
}
