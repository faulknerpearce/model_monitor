import AppKit
import SwiftUI

/// Renders the menu bar status as a single bitmap.
/// MenuBarExtra drops GeometryReader / Circle SwiftUI, so we draw explicitly.
///
/// Composites enabled provider segments: Grok (always) + optional OpenCode + optional Cursor.
///
/// The mutable statics (image cache, cached appearance, observer) are isolated
/// to the main actor since rendering drives off SwiftUI's main-actor label.
@MainActor
enum MenuBarStatusRenderer {
    private static let _cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 40
        return cache
    }()

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
        ensureAppearanceObserver()

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
        let chrome = menuBarAppearanceName
        let grok = snapshot.map { Int($0.usedPercent.rounded()) } ?? -1
        let openCode = openCodeSnapshot.map { Int($0.primaryUsedPercent.rounded()) } ?? -1
        let cursor = cursorSnapshot.map { Int($0.usedPercent.rounded()) } ?? -1

        let productKey = grokProducts
            .map { "\($0.id):\(Int($0.percentOfPool.rounded()))" }
            .joined(separator: ",")
        let productIDs = visibleProductIDs.sorted().joined(separator: ",")
        let parts = [
            "mb-\(grok)-\(openCode)-\(cursor)",
            "\(isGrokSignedIn)-\(showGrokBar)-\(showGrokCategories)-\(showOpenCodeBar)-\(showCursorBar)",
            "\(productKey)-\(productIDs)-\(chrome)"
        ]
        return parts.joined(separator: "-")
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
            let usedPercent: Double?
            let text: String
            let textSize: NSSize
            let color: NSColor
            let icon: NSImage
            let iconInset: CGFloat
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
                drawSolidBar(in: barRect, usedPercent: snap.usedPercent, color: nsColor(.chat))
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
        // Draw into the target rect without mutating the shared icon's size.
        icon.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: drawRect.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawGrokIcon(in rect: NSRect) {
        drawProviderIcon(ProviderLogo.grok, in: rect, inset: 0)
    }

    private static func menuBarProducts(
        from snapshot: WeeklyUsageSnapshot,
        visibleProductIDs: Set<String>
    ) -> [ProductUsage] {
        ProductCatalog.filtered(
            snapshot.products,
            visible: visibleProductIDs,
            threshold: 0.05
        )
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
        token.sRGB.nsColor
    }

    private static var chromeColor: NSColor {
        var cg: CGColor = .black
        menuBarAppearance().performAsCurrentDrawingAppearance {
            cg = NSColor.labelColor.cgColor
        }
        return NSColor(cgColor: cg) ?? .labelColor
    }

    private static var menuBarAppearanceName: String {
        let bestMatch = menuBarAppearance().bestMatch(from: [.darkAqua, .aqua])
        return bestMatch?.rawValue ?? menuBarAppearance().name.rawValue
    }

    private static func menuBarAppearance() -> NSAppearance {
        for window in NSApp.windows {
            let name = window.className
            if name.contains("StatusBar") || name.contains("MenuBarExtra") || name.contains("NSStatusItem") {
                return window.effectiveAppearance
            }
        }
        return NSApp.effectiveAppearance
    }

    private static func ensureAppearanceObserver() {
        guard appearanceObserver == nil else { return }
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            _cache.removeAllObjects()
        }
    }
}
