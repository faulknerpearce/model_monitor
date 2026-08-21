import SwiftUI

/// Standard "Sign In to <Provider>…" call-to-action for provider surfaces.
///
/// Every panel renders its sign-in affordance through this component so the
/// wording stays consistent per provider and the button always lives inside
/// its owning provider card or section instead of floating free in the panel.
///
/// - Parameters:
///   - provider: Provider whose sign-in flow this button opens; supplies the default label.
///   - title: Overrides the generated label (e.g. "Sign In Again…"); `nil` uses the standard one.
///   - font: Button font; defaults to the panel body size.
///   - action: Invoked on press; typically opens the provider's sign-in sheet.
struct ProviderSignInButton: View {
    let provider: MonitorProvider
    var title: String?
    var font: Font = PanelTypography.body
    let action: () -> Void

    var body: some View {
        Button(title ?? "Sign In to \(provider.displayName)…", action: action)
            .font(font)
    }
}
