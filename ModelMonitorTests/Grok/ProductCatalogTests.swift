@testable import ModelMonitor
import XCTest

final class ProductCatalogTests: XCTestCase {
    private func product(_ id: String, _ pct: Double) -> ProductUsage {
        ProductUsage(id: id, displayName: ProductCatalog.displayName(for: id), percentOfPool: pct)
    }

    func testFilteredKeepsVisibleAboveThreshold() {
        let products = [
            product("chat", 50),
            product("build", 30),
            product("api", 2)
        ]
        let result = ProductCatalog.filtered(
            products,
            visible: ["chat", "build", "api"],
            threshold: 5
        )
        XCTAssertEqual(result.map(\.id), ["chat", "build"])
    }

    func testFilteredExcludesHiddenProducts() {
        let products = [product("chat", 50), product("api", 10)]
        let result = ProductCatalog.filtered(products, visible: ["chat"], threshold: 0)
        XCTAssertEqual(result.map(\.id), ["chat"])
    }

    func testFilteredOrdersByDisplayOrder() {
        let products = [product("other", 30), product("chat", 40), product("build", 20)]
        let result = ProductCatalog.filtered(products, visible: ["other", "chat", "build"], threshold: 0)
        XCTAssertEqual(result.map(\.id), ["chat", "build", "other"])
    }

    func testFilteredEmptyWhenNoneAboveThreshold() {
        let products = [product("chat", 3), product("api", 1)]
        let result = ProductCatalog.filtered(products, visible: ["chat", "api"], threshold: 5)
        XCTAssertTrue(result.isEmpty)
    }
}
