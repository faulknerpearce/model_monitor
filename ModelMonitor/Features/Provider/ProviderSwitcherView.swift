import SwiftUI

struct ProviderSwitcherView: View {
    @Binding var selection: MonitorProvider

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MonitorProvider.allCases) { provider in
                Button {
                    selection = provider
                } label: {
                    HStack(spacing: 4) {
                        providerIcon(provider)
                        Text(provider.displayName)
                            .font(selection == provider ? PanelTypography.bodySemibold : PanelTypography.body)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        selection == provider
                            ? Color.accentColor.opacity(0.22)
                            : Color.primary.opacity(0.06)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func providerIcon(_ provider: MonitorProvider) -> some View {
        switch provider {
        case .overview:
            Image(systemName: "circle.grid.cross")
                .font(PanelTypography.captionSemibold)
                .frame(width: 12, height: 12)
        case .grok, .opencode, .cursor:
            Image(nsImage: ProviderLogo.image(for: provider))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
        }
    }
}
