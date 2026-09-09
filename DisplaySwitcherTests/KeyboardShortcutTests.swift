import Carbon
import XCTest

final class KeyboardShortcutTests: XCTestCase {
    func testSafetyRejectsSingleModifier() {
        let optOnly = KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(optionKey))
        let ctrlOnly = KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(controlKey))
        let cmdOnly = KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey))
        let shiftOnly = KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(shiftKey))
        XCTAssertFalse(optOnly.usesSafeModifierCombination)
        XCTAssertFalse(ctrlOnly.usesSafeModifierCombination)
        XCTAssertFalse(cmdOnly.usesSafeModifierCombination)
        XCTAssertFalse(shiftOnly.usesSafeModifierCombination)
    }

    func testSafetyAllowsTwoModifiers() {
        let cmdOpt = KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey | optionKey))
        let ctrlShift = KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(controlKey | shiftKey))
        let ctrlCmdOpt = KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(controlKey | cmdKey | optionKey))
        XCTAssertTrue(cmdOpt.usesSafeModifierCombination)
        XCTAssertTrue(ctrlShift.usesSafeModifierCombination)
        XCTAssertTrue(ctrlCmdOpt.usesSafeModifierCombination)
    }

    func testSafetyRejectsNoModifiers() {
        let none = KeyboardShortcut(keyCode: 0, carbonModifiers: 0)
        XCTAssertFalse(none.usesSafeModifierCombination)
    }

    func testDisplayLabelIncludesAllModifiers() {
        let s = KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
        let label = s.displayLabel
        XCTAssertTrue(label.contains("⌘"))
        XCTAssertTrue(label.contains("⌥"))
        XCTAssertTrue(label.contains("⌃"))
        XCTAssertTrue(label.contains("⇧"))
        XCTAssertTrue(label.contains("A"))
    }

    func testCatalogueCoversCommonKeys() {
        let codes = Set(KeyboardShortcut.catalogue.map { $0.keyCode })
        XCTAssertTrue(codes.contains(0))   // A
        XCTAssertTrue(codes.contains(49))  // Space
        XCTAssertTrue(codes.contains(36))  // Return
        XCTAssertTrue(codes.contains(53))  // Escape
        XCTAssertTrue(codes.contains(122)) // F1
        XCTAssertTrue(codes.contains(111)) // F12
    }
}
