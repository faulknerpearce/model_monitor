import SwiftUI

/// Modest "Sign out" affordance for signed-in provider surfaces.
///
/// Renders as a full-width, right-aligned row placed at the trailing edge of a
/// provider card. The idle state is a single tertiary icon; because sign-out
/// clears the persisted session, pressing it swaps the row to an inline
/// confirm/cancel pair rather than presenting a system alert — `MenuBarExtra`
/// panels mishandle modal alerts (the panel resigns key and the dialog strands
/// off-window), so confirmation stays inside the panel. Owning a full row (not
/// sharing the header line) guarantees the prompt renders untruncated in every
/// panel regardless of header width. The caller's `action` runs only after the
/// user confirms.
///
/// - Parameters:
///   - provider: Provider whose session this button ends; names the confirm prompt.
///   - font: Icon/prompt font; defaults to the panel caption size.
///   - action: Invoked after the user confirms; typically `auth.signOut()` plus
///     `poller.clearSnapshot()`.
struct ProviderSignOutButton: View {
    let provider: MonitorProvider
    var font: Font = PanelTypography.caption
    let action: () -> Void

    @State private var isConfirming = false

    var body: some View {
        HStack(spacing: 6) {
            Spacer()
            if isConfirming {
                confirmControls
            } else {
                signOutIcon
            }
        }
    }

    private var signOutIcon: some View {
        Button {
            isConfirming = true
        } label: {
            Image(systemName: "person.crop.circle.badge.minus")
                .font(font)
                .foregroundStyle(.tertiary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sign out")
        .accessibilityLabel("Sign out")
    }

    private var confirmControls: some View {
        Group {
            Text("Sign out of \(provider.displayName)?")
                .font(font)
                .foregroundStyle(.secondary)

            Button {
                isConfirming = false
                action()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(font)
                    .foregroundStyle(.red)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Confirm sign out")
            .accessibilityLabel("Confirm sign out")

            Button {
                isConfirming = false
            } label: {
                Image(systemName: "xmark.circle")
                    .font(font)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cancel")
            .accessibilityLabel("Cancel")
        }
    }
}
