import AppKit
import SwiftUI

enum ProviderLogo {
    static func image(for provider: MonitorProvider, size: CGFloat = 16) -> NSImage {
        switch provider {
        case .grok: return grok
        case .opencode: return openCode
        }
    }

    /// Official Grok singularity mark from the asset catalog (template, so SwiftUI tints it).
    static let grok: NSImage = {
        let image = (NSImage(named: "MenuBarIcon")?.copy() as? NSImage) ?? NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = true
        return image
    }()

    /// Official OpenCode square mark from the asset catalog.
    static let openCode: NSImage = {
        let image = (NSImage(named: "OpenCodeLogo")?.copy() as? NSImage)
            ?? NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = false
        return image
    }()
}

/// Section header with the provider logo, used in the menu dropdown.
struct ProviderHeaderLabel: View {
    let provider: MonitorProvider
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: ProviderLogo.image(for: provider, size: 14))
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
    }
}
