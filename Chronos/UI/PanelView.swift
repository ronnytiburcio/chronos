import SwiftUI

/// The things the panel cannot do for itself, handed in by the app delegate.
struct PanelActions {
    var onReset: () -> Void
    var onOpenSettings: () -> Void
}

/// The desktop panel's content (SPEC §5): header, project rows, footer.
///
/// Everything on screen is derived from ``TimerEngine``, which is
/// `@Observable`, so the times re-render each time its `now` ticks — there is
/// no timer in the view layer.
struct PanelView: View {
    let engine: TimerEngine
    let actions: PanelActions
    /// Called with the height the panel wants whenever the row count changes,
    /// so the window can grow and shrink with the list (SPEC §4).
    var onDesiredHeightChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                trackingDay: engine.lastRollover,
                calendar: engine.trackingCalendar,
                dayTotal: engine.dayTotal(asOf: engine.now)
            )

            divider

            if engine.visibleProjects.isEmpty {
                emptyState
            } else {
                projectList
            }

            divider

            FooterView(
                onAdd: { engine.addProject(named: $0) },
                onReset: actions.onReset,
                onOpenSettings: actions.onOpenSettings
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: engine.visibleProjects.count, initial: true) { _, count in
            onDesiredHeightChange(PanelLayout.height(rowCount: count))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.chronosPaper.opacity(0.1))
            .frame(height: PanelLayout.dividerHeight)
    }

    /// The list scrolls once it outgrows ``PanelLayout/maxHeight``; below that
    /// the window is exactly tall enough and the scroll view never moves.
    private var projectList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(engine.visibleProjects.enumerated()), id: \.element.id) { index, project in
                    ProjectRowView(
                        project: project,
                        isActive: engine.runningProject?.id == project.id,
                        elapsed: engine.total(for: project.id, asOf: engine.now),
                        canMoveUp: index > 0,
                        canMoveDown: index < engine.visibleProjects.count - 1,
                        actions: rowActions(for: project)
                    )
                }
            }
            .padding(.vertical, PanelLayout.listVerticalPadding)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        Text("No projects yet.\nAdd your first one below.")
            .font(.system(size: 12))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.chronosMuted)
            .padding(.horizontal, PanelLayout.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rowActions(for project: Project) -> ProjectRowActions {
        ProjectRowActions(
            onToggle: { engine.toggle(projectID: project.id) },
            onRename: { engine.renameProject(project.id, to: $0) },
            onSetColor: { engine.setColor($0, for: project.id) },
            onMove: { engine.moveProject(project.id, direction: $0) },
            onArchive: { engine.archiveProject(project.id) }
        )
    }
}
