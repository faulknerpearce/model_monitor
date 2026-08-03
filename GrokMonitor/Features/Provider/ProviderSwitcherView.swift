import SwiftUI

struct ProviderSwitcherView: View {
    @Binding var selection: MonitorProvider

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MonitorProvider.allCases) { provider in
                Button {
                    selection = provider
                } label: {
                    HStack(spacing: 5) {
                        providerIcon(provider)
                        Text(provider.displayName)
                            .font(.system(size: 12, weight: selection == provider ? .semibold : .regular))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        selection == provider
                            ? Color.accentColor.opacity(0.22)
                            : Color.primary.opacity(0.06)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func providerIcon(_ provider: MonitorProvider) -> some View {
        switch provider {
        case .overview:
            Image(systemName: "circle.grid.cross")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 12, height: 12)
        case .grok, .opencode:
            Image(nsImage: ProviderLogo.image(for: provider, size: 12))
                .resizable()
                .interpolation(.high)
                .frame(width: 12, height: 12)
        }
    }
}
