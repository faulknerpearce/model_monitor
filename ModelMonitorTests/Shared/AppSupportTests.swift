@testable import ModelMonitor
import XCTest

final class AppSupportTests: XCTestCase {
    func testDirectoryIsCreatedAsDirectory() throws {
        let dir = AppSupport.directory(subdirectory: "ModelMonitor-Tests-\(UUID().uuidString)")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testDefaultUsesExpectedSubdirectory() {
        let dir = AppSupport.directory()
        XCTAssertTrue(dir.path.contains("Application Support"))
        XCTAssertEqual(dir.lastPathComponent, "ModelMonitor")
    }
}
