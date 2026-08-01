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
                        Image(nsImage: ProviderLogo.image(for: provider, size: 12))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 12, height: 12)
                        Text(provider.displayName)
                            .font(.system(size: 12, weight: selection == provider ? .semibold : .regular))
                    }
                    .padding(.horizontal, 12)
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
            Spacer()
        }
    }
}
