import SwiftUI

/// The panel footer (SPEC §5): add a project, open the review window, reset the
/// day, open settings.
///
/// Both destructive-ish affordances stay inside the panel. Adding is an inline
/// field, and Reset is a two-step confirm in the footer itself rather than an
/// `NSAlert`, because an alert would activate Chronos and break the
/// never-steal-focus rule.
struct FooterView: View {
    var onAdd: (String) -> Void
    var onReset: () -> Void
    var onOpenReview: () -> Void
    var onOpenSettings: () -> Void

    private enum Mode: Equatable {
        case idle
        case adding
        case confirmingReset
    }

    /// How long the "Reset day?" confirm waits before giving up. Long enough to
    /// read, short enough that a stray click never leaves the footer armed.
    private static let confirmTimeout = Duration.seconds(6)

    @State private var mode: Mode = .idle
    @State private var draftName = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            switch mode {
            case .idle:
                addButton
                Spacer(minLength: 0)
                iconButtons
            case .adding:
                addField
            case .confirmingReset:
                resetConfirmation
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, PanelLayout.horizontalPadding)
        .frame(height: PanelLayout.footerHeight)
        .frame(maxWidth: .infinity)
        .task(id: mode) {
            guard mode == .confirmingReset else { return }
            try? await Task.sleep(for: Self.confirmTimeout)
            guard !Task.isCancelled else { return }
            mode = .idle
        }
    }

    // MARK: - Idle

    private var addButton: some View {
        HoverButton("+ Add project") {
            draftName = ""
            mode = .adding
        }
    }

    private var iconButtons: some View {
        HStack(spacing: 12) {
            HoverIconButton(symbol: "chart.bar", help: "Review") {
                onOpenReview()
            }
            HoverIconButton(symbol: "arrow.clockwise", help: "Reset day") {
                mode = .confirmingReset
            }
            HoverIconButton(symbol: "gearshape", help: "Settings") {
                onOpenSettings()
            }
        }
    }

    // MARK: - Adding

    private var addField: some View {
        TextField("Project name", text: $draftName)
            .textFieldStyle(.plain)
            .foregroundStyle(Color.chronosPaper)
            .focused($isFieldFocused)
            .onSubmit { commitAdd() }
            .onEscape(while: mode == .adding) { cancelAdd() }
            .task {
                // The panel is non-activating; it has to be made key by hand
                // before a field can take keystrokes.
                await PanelKeyWindow.makeKey()
                isFieldFocused = true
            }
    }

    private func commitAdd() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty submit means "never mind", per SPEC §5's inline field.
        guard !trimmed.isEmpty else {
            cancelAdd()
            return
        }
        onAdd(trimmed)
        draftName = ""
        // Stay in the field so several projects can be added in a row.
    }

    private func cancelAdd() {
        draftName = ""
        isFieldFocused = false
        mode = .idle
    }

    // MARK: - Reset confirmation

    private var resetConfirmation: some View {
        HStack(spacing: 8) {
            Text("Reset day?")
                .foregroundStyle(Color.chronosPaper)
            Spacer(minLength: 0)
            HoverButton("Confirm", tint: .chronosScarlet) {
                mode = .idle
                onReset()
            }
            HoverButton("Cancel") {
                mode = .idle
            }
        }
    }
}

/// A borderless text button that lifts from Muted to Paper on hover.
///
/// `.plain` rather than a bordered style so the first click lands without the
/// control wanting focus first — the panel never activates Chronos.
private struct HoverButton: View {
    let title: String
    let tint: Color?
    let action: () -> Void

    @State private var isHovering = false

    init(_ title: String, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(tint ?? (isHovering ? Color.chronosPaper : Color.chronosMuted))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(tint != nil && !isHovering ? 0.85 : 1)
        .onHover { isHovering = $0 }
    }
}

/// The footer's symbol buttons (chart, ⟳, ⚙).
private struct HoverIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovering ? Color.chronosPaper : Color.chronosMuted)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(help))
        .help(help)
    }
}
