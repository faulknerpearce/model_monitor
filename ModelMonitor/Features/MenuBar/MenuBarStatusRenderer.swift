import AppKit
import SwiftUI

/// Renders the menu bar status as a single bitmap.
/// MenuBarExtra drops GeometryReader / Circle SwiftUI, so we draw explicitly.
///
/// Composites enabled provider segments: Grok (always) + optional OpenCode + optional Cursor.
enum MenuBarStatusRenderer {
    private static let _cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 40
        return cache
    }()

    private static var cachedMenuBarIsDark: Bool?
    private static var appearanceObserver: NSObjectProtocol?

    static func image(
        snapshot: WeeklyUsageSnapshot?,
        openCodeSnapshot: OpenCodeSnapshot?,
        cursorSnapshot: CursorSnapshot?,
        isGrokSignedIn: Bool,
        showGrokBar: Bool,
        showGrokCategories: Bool,
        showOpenCodeBar: Bool,
        showCursorBar: Bool,
        visibleProductIDs: Set<String>
    ) -> NSImage {
        let grokProducts: [ProductUsage] = {
            guard let snapshot else { return [] }
            return menuBarProducts(from: snapshot, visibleProductIDs: visibleProductIDs)
        }()

        let cacheKey = _cacheKey(
            grokProducts: grokProducts,
            snapshot: snapshot,
            openCodeSnapshot: openCodeSnapshot,
            cursorSnapshot: cursorSnapshot,
            isGrokSignedIn: isGrokSignedIn,
            showGrokBar: showGrokBar,
            showGrokCategories: showGrokCategories,
            showOpenCodeBar: showOpenCodeBar,
            showCursorBar: showCursorBar,
            visibleProductIDs: visibleProductIDs
        )
        if let cached = _cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let image = _render(
            grokProducts: grokProducts,
            snapshot: snapshot,
            openCodeSnapshot: openCodeSnapshot,
            cursorSnapshot: cursorSnapshot,
            isGrokSignedIn: isGrokSignedIn,
            showGrokBar: showGrokBar,
            showGrokCategories: showGrokCategories,
            showOpenCodeBar: showOpenCodeBar,
            showCursorBar: showCursorBar
        )
        _cache.setObject(image, forKey: cacheKey as NSString)
        return image
    }

    private static func _cacheKey(
        grokProducts: [ProductUsage],
        snapshot: WeeklyUsageSnapshot?,
        openCodeSnapshot: OpenCodeSnapshot?,
        cursorSnapshot: CursorSnapshot?,
        isGrokSignedIn: Bool,
        showGrokBar: Bool,
        showGrokCategories: Bool,
        showOpenCodeBar: Bool,
        showCursorBar: Bool,
        visibleProductIDs: Set<String>
    ) -> String {
        let chrome = menuBarIsDark ? "dark" : "light"
        let g = snapshot.map { Int($0.usedPercent.rounded()) } ?? -1
        let o = openCodeSnapshot.map { Int($0.primaryUsedPercent.rounded()) } ?? -1
        let c = cursorSnapshot.map { Int($0.usedPercent.rounded()) } ?? -1
        let productKey = grokProducts
            .map { "\($0.id):\(Int($0.percentOfPool.rounded()))" }
            .joined(separator: ",")
        return "mb-\(g)-\(o)-\(c)-\(isGrokSignedIn)-\(showGrokBar)-\(showGrokCategories)-\(showOpenCodeBar)-\(showCursorBar)-\(productKey)-\(visibleProductIDs.sorted().joined(separator: ","))-\(chrome)"
    }

    private static func _render(
        grokProducts: [ProductUsage],
        snapshot: WeeklyUsageSnapshot?,
        openCodeSnapshot: OpenCodeSnapshot?,
        cursorSnapshot: CursorSnapshot?,
        isGrokSignedIn: Bool,
        showGrokBar: Bool,
        showGrokCategories: Bool,
        showOpenCodeBar: Bool,
        showCursorBar: Bool
    ) -> NSImage {
        let height: CGFloat = 22
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        let smallFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        let textColor = chromeColor
        let iconSize: CGFloat = 16
        let barWidth: CGFloat = 48
        let barHeight: CGFloat = 8
        let dotSize: CGFloat = 7
        let gap: CGFloat = 7
        let segmentGap: CGFloat = 10

        let usedAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: smallFont,
            .foregroundColor: textColor
        ]

        var width: CGFloat = 0

        let grokSigned = isGrokSignedIn && snapshot != nil
        let grokUsedText: String
        let grokUsedSize: NSSize
        let categoryLabels: [(label: String, size: NSSize)]
        if grokSigned, let snap = snapshot {
            grokUsedText = "\(Int(snap.usedPercent.rounded()))%"
            grokUsedSize = grokUsedText.size(withAttributes: usedAttrs)
            categoryLabels = showGrokCategories
                ? grokProducts.map {
                    let label = "\(ProductCatalog.shortName(for: $0.id)) \(Int($0.percentOfPool.rounded()))%"
                    return (label, label.size(withAttributes: labelAttrs))
                }
                : []
            width += iconSize + gap + grokUsedSize.width
            if showGrokBar { width += gap + barWidth }
            if showGrokCategories {
                for item in categoryLabels {
                    width += gap + dotSize + 4 + item.size.width
                }
            }
        } else {
            grokUsedText = "Grok"
            grokUsedSize = grokUsedText.size(withAttributes: usedAttrs)
            categoryLabels = []
            width += iconSize + gap + grokUsedSize.width
        }

        struct SolidSegment {
            var usedPercent: Double?
            var text: String
            var textSize: NSSize
            var color: NSColor
            var icon: NSImage
            var iconInset: CGFloat
        }

        var solidSegments: [SolidSegment] = []
        if showOpenCodeBar {
            let used = openCodeSnapshot?.primaryUsedPercent
            let text = used.map { "\(Int($0.rounded()))%" } ?? "—"
            let size = text.size(withAttributes: usedAttrs)
            solidSegments.append(SolidSegment(
                usedPercent: used,
                text: text,
                textSize: size,
                color: NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.20, alpha: 1),
                icon: ProviderLogo.openCode,
                iconInset: 2.5
            ))
            width += segmentGap + iconSize + gap + size.width + gap + barWidth
        }
        if showCursorBar {
            let used = cursorSnapshot?.usedPercent
            let text = used.map { "\(Int($0.rounded()))%" } ?? "—"
            let size = text.size(withAttributes: usedAttrs)
            solidSegments.append(SolidSegment(
                usedPercent: used,
                text: text,
                textSize: size,
                color: NSColor(calibratedRed: 0.15, green: 0.65, blue: 0.58, alpha: 1),
                icon: ProviderLogo.cursor,
                iconInset: 0
            ))
            width += segmentGap + iconSize + gap + size.width + gap + barWidth
        }

        width = ceil(width + 2)
        let image = NSImage(size: NSSize(width: max(width, 20), height: height))
        image.isTemplate = false
        image.lockFocus()
        defer { image.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high

        var x: CGFloat = 0
        let midY = height / 2

        // --- Grok ---
        drawGrokIcon(in: NSRect(x: x, y: midY - iconSize / 2, width: iconSize, height: iconSize))
        x += iconSize + gap

        grokUsedText.draw(
            at: NSPoint(x: x, y: midY - grokUsedSize.height / 2 - 0.5),
            withAttributes: usedAttrs
        )
        x += grokUsedSize.width

        if grokSigned, let snap = snapshot {
            if showGrokBar {
                x += gap
                let barRect = NSRect(x: x, y: midY - barHeight / 2, width: barWidth, height: barHeight)
                drawUsageBar(
                    in: barRect,
                    products: grokProducts.isEmpty
                        ? [ProductUsage(id: "used", displayName: "Used", percentOfPool: snap.usedPercent, colorToken: .chat)]
                        : grokProducts
                )
                x += barWidth
            }

            if showGrokCategories {
                for (product, item) in zip(grokProducts, categoryLabels) {
                    x += gap
                    let dotRect = NSRect(x: x, y: midY - dotSize / 2, width: dotSize, height: dotSize)
                    nsColor(product.colorToken).setFill()
                    NSBezierPath(ovalIn: dotRect).fill()
                    x += dotSize + 4
                    item.label.draw(
                        at: NSPoint(x: x, y: midY - item.size.height / 2 - 0.5),
                        withAttributes: labelAttrs
                    )
                    x += item.size.width
                }
            }
        }

        for segment in solidSegments {
            x += segmentGap
            let iconRect = NSRect(x: x, y: midY - iconSize / 2, width: iconSize, height: iconSize)
            drawProviderIcon(segment.icon, in: iconRect, inset: segment.iconInset)
            x += iconSize + gap

            segment.text.draw(
                at: NSPoint(x: x, y: midY - segment.textSize.height / 2 - 0.5),
                withAttributes: usedAttrs
            )
            x += segment.textSize.width + gap

            let barRect = NSRect(x: x, y: midY - barHeight / 2, width: barWidth, height: barHeight)
            drawSolidBar(in: barRect, usedPercent: segment.usedPercent ?? 0, color: segment.color)
            x += barWidth
        }

        return image
    }

    private static func drawUsageBar(in barRect: NSRect, products: [ProductUsage]) {
        drawBarTrack(in: barRect)
        var segX = barRect.minX
        let clip = NSBezierPath(roundedRect: barRect, xRadius: barRect.height / 2, yRadius: barRect.height / 2)
        for product in products {
            let segW = barRect.width * CGFloat(Percent.clamp(product.percentOfPool) / 100)
            guard segW > 0.5 else { continue }
            let segRect = NSRect(x: segX, y: barRect.minY, width: segW, height: barRect.height)
            nsColor(product.colorToken).setFill()
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            NSBezierPath(rect: segRect).fill()
            NSGraphicsContext.restoreGraphicsState()
            segX += segW
        }
    }

    private static func drawSolidBar(in barRect: NSRect, usedPercent: Double, color: NSColor) {
        drawBarTrack(in: barRect)
        guard usedPercent > 0 else { return }
        let fillWidth = barRect.width * CGFloat(Percent.clamp(usedPercent) / 100)
        let fillRect = NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barRect.height)
        color.setFill()
        let clip = NSBezierPath(roundedRect: barRect, xRadius: barRect.height / 2, yRadius: barRect.height / 2)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        NSBezierPath(rect: fillRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawBarTrack(in barRect: NSRect) {
        chromeColor.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: barRect.height / 2, yRadius: barRect.height / 2).fill()
    }

    private static func drawProviderIcon(_ icon: NSImage, in rect: NSRect, inset: CGFloat) {
        let drawRect = inset > 0 ? rect.insetBy(dx: inset, dy: inset) : rect
        NSGraphicsContext.saveGraphicsState()
        if icon.isTemplate {
            chromeColor.set()
        }
        icon.size = drawRect.size
        icon.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: icon.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Official Grok singularity mark (not the prohibition / "do not enter" circle-slash).
    private static let grokIconTemplate: NSImage? = {
        guard let image = NSImage(named: "MenuBarIcon") else { return nil }
        let copy = (image.copy() as? NSImage) ?? image
        copy.isTemplate = true
        return copy
    }()

    private static func drawGrokIcon(in rect: NSRect) {
        if let icon = grokIconTemplate {
            drawProviderIcon(icon, in: rect, inset: 0)
            return
        }
        drawGrokIconVector(in: rect)
    }

    /// Fallback geometry matching `MenuBarIcon.pdf` (16×16 artboard, official Grok mark).
    private static func drawGrokIconVector(in rect: NSRect) {
        let s = min(rect.width, rect.height) / 16
        let ox = rect.midX - 8 * s
        let oy = rect.midY - 8 * s

        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: ox + x * s, y: oy + y * s)
        }

        let path = NSBezierPath()

        path.move(to: p(6.385, 6.066))
        path.line(to: p(11.104, 9.554))
        path.curve(to: p(11.777, 9.393), controlPoint1: p(11.336, 9.725), controlPoint2: p(11.666, 9.659))
        path.curve(to: p(10.943, 5.153), controlPoint1: p(12.357, 7.992), controlPoint2: p(12.098, 6.309))
        path.curve(to: p(6.714, 4.321), controlPoint1: p(9.789, 3.997), controlPoint2: p(8.182, 3.743))
        path.line(to: p(5.110, 3.577))
        path.curve(to: p(11.950, 4.141), controlPoint1: p(7.411, 2.003), controlPoint2: p(10.204, 2.392))
        path.curve(to: p(13.362, 9.121), controlPoint1: p(13.335, 5.528), controlPoint2: p(13.763, 7.417))
        path.line(to: p(13.366, 9.118))
        path.curve(to: p(14.993, 14.668), controlPoint1: p(12.785, 11.621), controlPoint2: p(13.509, 12.622))
        path.curve(to: p(15.098, 14.815), controlPoint1: p(15.028, 14.716), controlPoint2: p(15.063, 14.765))
        path.line(to: p(13.146, 12.859))
        path.line(to: p(13.146, 12.866))
        path.line(to: p(6.383, 6.065))
        path.close()

        path.move(to: p(5.411, 5.218))
        path.curve(to: p(5.453, 10.651), controlPoint1: p(3.759, 6.797), controlPoint2: p(4.044, 9.241))
        path.curve(to: p(9.692, 11.494), controlPoint1: p(6.495, 11.694), controlPoint2: p(8.202, 12.120))
        path.line(to: p(11.292, 12.234))
        path.curve(to: p(10.210, 12.824), controlPoint1: p(11.004, 12.442), controlPoint2: p(10.634, 12.667))
        path.curve(to: p(4.441, 11.662), controlPoint1: p(8.294, 13.614), controlPoint2: p(5.999, 13.221))
        path.curve(to: p(3.281, 5.887), controlPoint1: p(2.943, 10.162), controlPoint2: p(2.472, 7.855))
        path.curve(to: p(1.896, 2.324), controlPoint1: p(3.885, 4.415), controlPoint2: p(2.894, 3.375))
        path.curve(to: p(0.902, 1.185), controlPoint1: p(1.542, 1.952), controlPoint2: p(1.187, 1.580))
        path.line(to: p(5.409, 5.217))
        path.close()

        chromeColor.setFill()
        path.fill()
    }

    private static func menuBarProducts(
        from snapshot: WeeklyUsageSnapshot,
        visibleProductIDs: Set<String>
    ) -> [ProductUsage] {
        let byID = Dictionary(
            snapshot.products.map { ($0.id.lowercased(), $0) },
            uniquingKeysWith: { _, last in last }
        )
        return ProductCatalog.displayOrder.compactMap { id in
            guard visibleProductIDs.contains(id),
                  let product = byID[id],
                  product.percentOfPool > 0.05
            else { return nil }
            return product
        }
    }

    private static func nsColor(_ token: ProductColor) -> NSColor {
        colorCache[token] ?? makeColor(token)
    }

    private static let colorCache: [ProductColor: NSColor] = {
        ProductColor.allCases.reduce(into: [:]) { cache, token in
            cache[token] = makeColor(token)
        }
    }()

    private static func makeColor(_ token: ProductColor) -> NSColor {
        let c = token.sRGB
        return NSColor(calibratedRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    private static var chromeColor: NSColor {
        menuBarIsDark ? .white : .black
    }

    private static var menuBarIsDark: Bool {
        if let cached = cachedMenuBarIsDark {
            return cached
        }
        let value = resolveMenuBarIsDark()
        cachedMenuBarIsDark = value
        ensureAppearanceObserver()
        return value
    }

    private static func resolveMenuBarIsDark() -> Bool {
        for window in NSApp.windows {
            let name = window.className
            if name.contains("StatusBar") || name.contains("MenuBarExtra") || name.contains("NSStatusItem") {
                return window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
        }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func ensureAppearanceObserver() {
        guard appearanceObserver == nil else { return }
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            cachedMenuBarIsDark = nil
            _cache.removeAllObjects()
        }
    }
}
