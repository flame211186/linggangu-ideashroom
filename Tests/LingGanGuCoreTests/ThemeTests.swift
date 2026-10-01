import XCTest
@testable import LingGanGuCore

final class ThemeTests: XCTestCase {
    func testBuiltInThemeIsValid() throws {
        try ThemeValidator.validate(.glassSporeMushroom)
    }

    func testThemeRejectsPathTraversal() {
        var theme = ThemeManifest.glassSporeMushroom
        theme.assetNames = ["../../secret"]

        XCTAssertThrowsError(try ThemeValidator.validate(theme)) { error in
            XCTAssertEqual(
                error as? ThemeValidationError,
                .invalidAssetName("../../secret")
            )
        }
    }

    func testThemeRejectsExecutableAssets() {
        var theme = ThemeManifest.glassSporeMushroom
        theme.assetNames = ["theme.swift"]

        XCTAssertThrowsError(try ThemeValidator.validate(theme))
    }
}
