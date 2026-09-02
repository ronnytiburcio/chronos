import SwiftUI

/// What a project row can ask the engine to do. Passed in rather than reached
/// for, so the row stays a plain view over plain values.
struct ProjectRowActions {
    var onToggle: () -> Void
    var onRename: (String) -> Void
    var onSetColor: (String?) -> Void
    var onMove: (MoveDirection) -> Void
    var onArchive: () -> Void
}

/// One project in the panel list (SPEC §5, "Project row").
///
/// The whole row is the hit target: there are no small buttons to aim at, and
/// the click must land on the *first* press without Chronos activating, which
/// is why this is a `.plain` button over a `contentShape`d row rather than a
/// styled control that wants focus first.
struct ProjectRowView: View {
    let project: Project
    let isActive: Bool
    /// Seconds tracked on this project so far today.
    let elapsed: TimeInterval
    let canMoveUp: Bool
    let canMoveDown: Bool
    let actions: ProjectRowActions

    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var menuPresenter = RowMenuPresenter()
    @FocusState private var isNameFieldFocused: Bool

    /// The row's own color, or Scarlet when it has none.
    private var accent: Color { project.displayColor }

    var body: some View {
        Group {
            if isRenaming {
                renameRow
            } else {
                displayRow
            }
        }
        .frame(height: PanelLayout.rowHeight)
        .padding(.horizontal, PanelLayout.horizontalPadding - PanelLayout.rowInset)
        // Behind the row so a right-click anywhere on it reaches `menu(for:)`;
        // the "•••" button pops the same menu explicitly.
        .background(RowMenuAnchor(makeMenu: buildMenu).presenting(menuPresenter))
    }

    // MARK: - Display

    private var displayRow: some View {
        Button(action: actions.onToggle) {
            HStack(spacing: 8) {
                ActivityDot(color: accent, isActive: isActive)

                Text(project.name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isActive ? Color.chronosPaper : Color.chronosMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isActive {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(accent)
                }

                Spacer(minLength: 6)

                Text(TimeFormatting.hms(elapsed))
                    .font(.system(size: 12, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(isActive ? Color.chronosPaper : Color.chronosMuted)

                menuButton
            }
            .padding(.horizontal, PanelLayout.rowInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(isActive ? 0.18 : 0))
            )
            // The tint is only painted where the row is active, so the hit
            // target is declared separately and covers the whole row.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(project.name))
        .accessibilityValue(Text(isActive ? "Running" : "Stopped"))
    }

    // MARK: - Menu

    /// The "•••" affordance. A nested button wins over the row button, so a
    /// click here opens the menu instead of toggling the timer.
    private var menuButton: some View {
        Button {
            menuPresenter.present()
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.chronosPaper.opacity(0.75))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Project menu"))
        .help("Rename, color, reorder, archive")
    }

    /// Rename, Change color, Move up/down, Archive — as an AppKit menu, which
    /// is the only kind that opens while Chronos is not the active app.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(ClosureMenuItem("Rename") { beginRenaming() })

        let colors = NSMenu()
        colors.autoenablesItems = false
        for option in ProjectColorOptions.all {
            let isCurrent = (option.hex?.uppercased()) == (project.colorHex?.uppercased())
            colors.addItem(ClosureMenuItem(
                option.name,
                state: isCurrent ? .on : .off,
                image: Self.swatch(for: option)
            ) { actions.onSetColor(option.hex) })
        }
        let colorItem = NSMenuItem(title: "Change color", action: nil, keyEquivalent: "")
        colorItem.submenu = colors
        menu.addItem(colorItem)

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Move up", enabled: canMoveUp) { actions.onMove(.up) })
        menu.addItem(ClosureMenuItem("Move down", enabled: canMoveDown) { actions.onMove(.down) })

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Archive") { actions.onArchive() })
        return menu
    }

    private static func swatch(for option: ProjectColorOption) -> NSImage? {
        let color = (option.hex.flatMap(PaletteColor.init(hexString:)) ?? Palette.scarlet).nsColor
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            .applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: option.name)?
            .withSymbolConfiguration(configuration)
    }

    // MARK: - Rename

    /// Renaming happens in place: the name swaps for a field, Enter commits,
    /// Escape puts the row back. No sheet, no alert — either would activate
    /// Chronos and break the never-steal-focus rule.
    private var renameRow: some View {
        HStack(spacing: 8) {
            ActivityDot(color: accent, isActive: isActive)

            TextField("Project name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.chronosPaper)
                .focused($isNameFieldFocused)
                .onSubmit { commitRename() }
                .onEscape(while: isRenaming) { cancelRename() }
        }
        .padding(.horizontal, PanelLayout.rowInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.chronosPaper.opacity(0.08))
        )
        .task {
            // The panel is non-activating, so it has to be made key by hand
            // for the field to take keystrokes. This does not activate Chronos.
            await PanelKeyWindow.makeKey()
            isNameFieldFocused = true
        }
    }

    private func beginRenaming() {
        draftName = project.name
        isRenaming = true
    }

    private func commitRename() {
        actions.onRename(draftName)
        endRenaming()
    }

    private func cancelRename() {
        endRenaming()
    }

    private func endRenaming() {
        isRenaming = false
        isNameFieldFocused = false
        draftName = ""
    }
}

/// The left-hand state indicator: filled and gently pulsing while the project
/// is running, a hollow Muted ring while it is idle (SPEC §5, §9).
private struct ActivityDot: View {
    let color: Color
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    private static let diameter: CGFloat = 8
    private static let period: TimeInterval = 1.2

    var body: some View {
        Group {
            if isActive {
                Circle().fill(color)
            } else {
                Circle().strokeBorder(Color.chronosMuted, lineWidth: 1.5)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .opacity(dimmed ? 0.55 : 1)
        .onAppear { updatePulse() }
        .onChange(of: isActive) { _, _ in updatePulse() }
        .onChange(of: reduceMotion) { _, _ in updatePulse() }
    }

    private func updatePulse() {
        guard isActive, !reduceMotion else {
            // Drop straight back to full opacity; animating to it would leave
            // the repeating animation running.
            withTransaction(Transaction(animation: nil)) { dimmed = false }
            return
        }
        withAnimation(.easeInOut(duration: Self.period).repeatForever(autoreverses: true)) {
            dimmed = true
        }
    }
}
