import SwiftUI

/// Equal-width segmented control at the top of the menu dropdown.
struct ProviderSwitcherView: View {
    @Binding var selection: MonitorProvider

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(MonitorProvider.allCases.enumerated()), id: \.element.id) { index, provider in
                if index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1)
                }
                Button {
                    selection = provider
                } label: {
                    HStack(spacing: 4) {
                        if provider != .overview {
                            Image(nsImage: ProviderLogo.image(for: provider))
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                        }
                        Text(provider.switcherLabel)
                            .font(selection == provider ? PanelTypography.captionSemibold : PanelTypography.caption)
                            .foregroundStyle(selection == provider ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                    .background(
                        selection == provider
                            ? Color.primary.opacity(0.08)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}
