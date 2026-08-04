import XCTest
@testable import ModelMonitor

final class OpenCodeConsoleClientTests: XCTestCase {
    func testLiteSubscriptionServerIDDiscovery() {
        let js = """
        const queryLiteSubscription_query = createServerReference("c7389bd0e731f80f49593e5ee53835475f4e28594dd6bd83eb229bab753498cd");
        const queryLiteSubscription = query(queryLiteSubscription_query, "lite.subscription.get");
        """
        let id = OpenCodeConsoleClient.liteSubscriptionServerID(fromChunkJS: js)
        XCTAssertEqual(id, "c7389bd0e731f80f49593e5ee53835475f4e28594dd6bd83eb229bab753498cd")
    }

    func testGoRouteChunkDiscovery() {
        let entry = """
        "src": "src/routes/workspace/[id]/go/index.tsx?pick=default&pick=$css", "build": () => __vitePreload(() => import(
          /* @vite-ignore */
          "./index-CVdbz_I8.js"
        )), true ? __vite__mapDeps([66]) : void 0) }, "path": "/workspace/:id/go/" },
        """
        let name = OpenCodeConsoleClient.goRouteChunkName(fromEntryClient: entry)
        XCTAssertEqual(name, "index-CVdbz_I8.js")
    }

    func testWorkspaceIDFromURL() {
        let url = URL(string: "https://opencode.ai/workspace/wrk_01KTEST123/go")!
        XCTAssertEqual(OpenCodeConsoleClient.workspaceID(from: url), "wrk_01KTEST123")
        XCTAssertNil(OpenCodeConsoleClient.workspaceID(from: URL(string: "https://opencode.ai/auth")!))
    }

    func testParseLiteSubscriptionJS() throws {
        let body = #"""
        ;0x00000131;((self.$R=self.$R||{})["s"]=[],($R=>$R[0]={mine:!0,useBalance:!0,region:$R[1]=["us","eu","sg"],rollingUsage:$R[2]={status:"ok",resetInSec:18000,usagePercent:0},weeklyUsage:$R[3]={status:"ok",resetInSec:104231,usagePercent:88},monthlyUsage:$R[4]={status:"ok",resetInSec:1281053,usagePercent:62}})($R["s"]))
        """#
        let parsed = try OpenCodeConsoleClient.parseLiteSubscriptionJS(body)
        XCTAssertTrue(parsed.mine)
        XCTAssertEqual(parsed.rolling.0, 0, accuracy: 0.01)
        XCTAssertEqual(parsed.rolling.1, 18_000, accuracy: 1)
        XCTAssertEqual(parsed.weekly.0, 88, accuracy: 0.01)
        XCTAssertEqual(parsed.weekly.1, 104_231, accuracy: 1)
        XCTAssertEqual(parsed.monthly.0, 62, accuracy: 0.01)
        XCTAssertEqual(parsed.monthly.1, 1_281_053, accuracy: 1)
    }

    func testOpenCodeDomainFilter() {
        XCTAssertTrue(OpenCodeAuthSession.isOpenCodeDomain("opencode.ai"))
        XCTAssertTrue(OpenCodeAuthSession.isOpenCodeDomain(".opencode.ai"))
        XCTAssertTrue(OpenCodeAuthSession.isOpenCodeDomain("auth.opencode.ai"))
        XCTAssertFalse(OpenCodeAuthSession.isOpenCodeDomain("grok.com"))
    }
}
