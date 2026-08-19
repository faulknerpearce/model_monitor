import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    let snapshot: WeeklyUsageSnapshot?
    let openCodeSnapshot: OpenCodeSnapshot?
    let cursorSnapshot: CursorSnapshot?
    let isGrokSignedIn: Bool
    let showGrokBar: Bool
    let showGrokCategories: Bool
    let showOpenCodeBar: Bool
    let showCursorBar: Bool
    let visibleProductIDs: Set<String>

    @Environment(\.colorScheme) private var colorScheme

    private var labelID: String {
        let products = visibleProductIDs.sorted().joined(separator: ",")
        let used = snapshot.map { Int($0.usedPercent.rounded()) } ?? -1
        let openCodeUsed = openCodeSnapshot.map { Int($0.primaryUsedPercent.rounded()) } ?? -1
        let cursorUsed = cursorSnapshot.map { Int($0.usedPercent.rounded()) } ?? -1
        let parts = [
            "\(showGrokBar)-\(showGrokCategories)-\(showOpenCodeBar)-\(showCursorBar)",
            "\(products)-\(used)-\(openCodeUsed)-\(cursorUsed)-\(isGrokSignedIn)-\(colorScheme)"
        ]
        return parts.joined(separator: "-")
    }

    var body: some View {
        Image(nsImage: MenuBarStatusRenderer.image(
            snapshot: snapshot,
            openCodeSnapshot: openCodeSnapshot,
            cursorSnapshot: cursorSnapshot,
            isGrokSignedIn: isGrokSignedIn,
            showGrokBar: showGrokBar,
            showGrokCategories: showGrokCategories,
            showOpenCodeBar: showOpenCodeBar,
            showCursorBar: showCursorBar,
            visibleProductIDs: visibleProductIDs
        ))
        .renderingMode(.original)
        .id(labelID)
    }
}
