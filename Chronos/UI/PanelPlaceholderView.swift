import SwiftUI

/// Phase 2 stand-in for the real panel UI. Every element here exists to prove
/// one property of the desktop panel; Phase 4 replaces the whole view.
///
/// - the header drags the window (and only the header),
/// - the button counts clicks, proving the first click lands without Chronos
///   activating,
/// - the text field takes keystrokes and echoes them, proving key input in a
///   non-activating panel,
/// - the last row carries a context menu, proving right-click.
///
/// Phase 3 adds the "Debug engine" section underneath: enough of a project
/// list to start, stop, and switch timers so the engine and its persistence
/// can be exercised before Phase 4 builds the real UI.
struct PanelPlaceholderView: View {
    let engine: TimerEngine

    @State private var tapCount = 0
    @State private var typedText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider().overlay(Color.chronosPaper.opacity(0.1))
            tapProof
            typingProof
            contextMenuProof
            Divider().overlay(Color.chronosPaper.opacity(0.1))
            debugEngine
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Color.chronosPaper)
        .font(.system(size: 12))
    }

    private var header: some View {
        HStack {
            Text("⚡ CHRONOS")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
            Spacer()
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        // Only this row moves the panel.
        .overlay(DragHandleView())
    }

    private var tapProof: some View {
        HStack(spacing: 10) {
            Button("Tap me") { tapCount += 1 }
                .buttonStyle(.borderedProminent)
                .tint(Color.chronosScarlet)
            Text("Taps: \(tapCount)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.chronosMuted)
        }
    }

    private var typingProof: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Type here", text: $typedText)
                .textFieldStyle(.roundedBorder)
            Text(typedText.isEmpty ? "Echo: (nothing typed yet)" : "Echo: \(typedText)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.chronosMuted)
                .lineLimit(2)
        }
    }

    private var contextMenuProof: some View {
        Text("Right-click me")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.chronosPaper.opacity(0.06))
            )
            .contentShape(Rectangle())
            .contextMenu {
                Button("Menu item works") {}
            }
    }

    // MARK: - Debug engine

    /// Times re-render because `engine.now` is `@Observable` and ticks once a
    /// second while a session is open.
    private var debugEngine: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEBUG ENGINE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.chronosMuted)

            if engine.visibleProjects.isEmpty {
                Button("Add \"Project A\"") { engine.addProject(named: "Project A") }
                    .buttonStyle(.bordered)
            } else {
                ForEach(engine.visibleProjects) { project in
                    projectRow(project)
                }
            }

            HStack {
                Text("Day total")
                Spacer()
                Text(TimeFormatting.hms(engine.dayTotal(asOf: engine.now)))
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color.chronosGold)
        }
    }

    private func projectRow(_ project: Project) -> some View {
        let isRunning = engine.runningProject?.id == project.id
        return Button {
            engine.toggle(projectID: project.id)
        } label: {
            HStack {
                Text(project.name)
                Spacer()
                Text(TimeFormatting.hms(engine.total(for: project.id, asOf: engine.now)))
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.chronosScarlet.opacity(isRunning ? 0.22 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isRunning ? Color.chronosScarlet : Color.chronosPaper)
    }
}
