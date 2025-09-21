#if os(macOS)
import XCTest
import AppKit
@testable import Features
@testable import Services
@testable import Models
@testable import Core

/// Simple test to verify keyboard handling works
@MainActor
final class SimpleKeyboardTest: XCTestCase {

    func testBasicKeyboardHandling() {
        // Create a TreeViewModel
        let viewModel = TreeViewModel()

        // Test that arrow keys return true (are handled)
        XCTAssertTrue(viewModel.handleKeyPress(keyCode: 126, modifiers: []), "Up arrow (126) should be handled")
        XCTAssertTrue(viewModel.handleKeyPress(keyCode: 125, modifiers: []), "Down arrow (125) should be handled")
        XCTAssertTrue(viewModel.handleKeyPress(keyCode: 123, modifiers: []), "Left arrow (123) should be handled")
        XCTAssertTrue(viewModel.handleKeyPress(keyCode: 124, modifiers: []), "Right arrow (124) should be handled")

        // Test creation shortcuts
        XCTAssertTrue(viewModel.handleKeyPress(keyCode: 17, modifiers: []), "T key (17) should be handled")
        XCTAssertTrue(viewModel.handleKeyPress(keyCode: 45, modifiers: []), "N key (45) should be handled")

        // Test command shortcuts
        XCTAssertTrue(viewModel.handleKeyPress(keyCode: 44, modifiers: .command), "Cmd+/ should be handled")

        print("✅ All basic keyboard tests passed!")
    }
}
#endif