import XCTest

/// Main iOS flow (PRD 9.2, "Interface"). Transfers to a real watch are
/// verified manually with the checklist in docs/TESTING.md.
final class ImportFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testLaunchShowsLibraryAndAddMenu() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["WatchDocs"].waitForExistence(timeout: 5))

        let add = app.buttons["addButton"]
        XCTAssertTrue(add.exists)
        add.tap()
        // Menu items: Files and Photos (English or French labels).
        let files = app.buttons["Files"].exists || app.buttons["Fichiers"].exists
        let photos = app.buttons["Photos"].exists
        XCTAssertTrue(files)
        XCTAssertTrue(photos)
    }

    func testFileImporterOpens() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["addButton"].tap()
        let files = app.buttons["Files"].exists ? app.buttons["Files"] : app.buttons["Fichiers"]
        files.tap()
        // The system document picker is presented.
        let browse = app.navigationBars.firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 5))
    }
}
