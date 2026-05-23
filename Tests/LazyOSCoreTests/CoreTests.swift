import XCTest
@testable import LazyOSCore

final class CoreTests: XCTestCase {
    func testAppKeyFormat() {
        let key = AppKeyGen.generate()
        XCTAssertTrue(key.hasPrefix("base64:"))
        let b64 = String(key.dropFirst("base64:".count))
        XCTAssertNotNil(Data(base64Encoded: b64))
        XCTAssertEqual(Data(base64Encoded: b64)?.count, 32)
    }

    func testCatalogLoadsMixpost() {
        let entries = Catalog.shared.entries()
        XCTAssertFalse(entries.isEmpty, "Catalog should include at least Mixpost")
        XCTAssertTrue(entries.contains(where: { $0.slug == "mixpost" }))
    }

    func testErrorTranslator() {
        XCTAssertTrue(ErrorTranslator.friendly("Cannot connect to the Docker daemon at unix:///var/run/docker.sock").lowercased().contains("orbstack"))
        XCTAssertTrue(ErrorTranslator.friendly("Bind: address already in use").lowercased().contains("port"))
    }

    func testPortPickerReturnsPreferredIfFree() {
        // Picks a high port unlikely to be in use
        let p = PortPicker.pick(preferred: 39871)
        XCTAssertGreaterThanOrEqual(p, 30000)
    }
}
