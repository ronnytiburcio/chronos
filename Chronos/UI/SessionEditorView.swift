import SwiftUI

/// The session editor's content: today's sessions, each with its project,
/// start, and end open for correction.
///
/// Scope is deliberately today only — sessions whose `start >= lastRollover`.
/// Everything older has already been written into the archive CSVs, which are
/// append-only, so changing it would mean rewriting a day that has been filed.
///
/// Like ``SettingsView`` this is an ordinary window: system appearance, system
/// control styling, and the project swatch as the only Chronos color. The
/// project rows are a `ForEach` inside a `Section` rather than a `List`, which
/// collapses to an ambiguous height inside a grouped `Form` on macOS 14.
struct SessionEditorView: View {
    let engine: TimerEngine
    /// Which project the list is filtered to, owned by the window controller so
    /// a second "Edit today's sessions…" from another row re-filters the window
    /// that is already open.
    @Bindable var state: SessionEditorState

    var body: some View {
        Form {
            Section {
                Picker("Project", selection: $state.projectFilter) {
                    Text("All projects").tag(UUID?.none)
                    ForEach(filterableProjects) { project in
                        Text(project.name).tag(UUID?.some(project.id))
                    }
                }
            }

            Section {
                if visibleSessions.isEmpty {
                    Text("Nothing tracked yet today.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleSessions) { session in
                        SessionEditRow(engine: engine, session: session)
                    }
                }
            } header: {
                Text("Today · \(TrackingDateLabel.string(for: engine.lastRollover, calendar: engine.trackingCalendar))")
            } footer: {
                Text("Only today's sessions can be edited. Earlier days are already in the archive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: SessionEditorWindowController.contentSize.width, minHeight: 0)
    }

    /// Everything tracked since the last rollover, oldest first. The one place
    /// "today" is worked out; both the list and the filter read it.
    private var todaysSessions: [Session] {
        engine.sessions
            .filter { $0.start >= engine.lastRollover }
            .sorted { $0.start < $1.start }
    }

    /// Today's sessions narrowed to the chosen project.
    private var visibleSessions: [Session] {
        todaysSessions.filter { state.projectFilter == nil || $0.projectID == state.projectFilter }
    }

    /// What the filter offers: the panel's projects, plus an archived one when
    /// it has time on the board today or is the current selection — a picker
    /// must never show a selection that is not among its own tags.
    private var filterableProjects: [Project] {
        let todaysProjectIDs = Set(todaysSessions.map(\.projectID))
        return engine.projects.filter {
            !$0.isArchived || todaysProjectIDs.contains($0.id) || $0.id == state.projectFilter
        }
    }
}

/// One editable session (SPEC's session editor). Its own struct for the same
/// reason `ProjectSettingsRow` is: the drafts are per-row `@State`.
///
/// Nothing is written until Save. The pickers read and write local drafts, so a
/// half-finished correction cannot land on disk, and `Revert` is just "put the
/// session's own values back". Only ``RunningDurationLabel`` reads `engine.now`,
/// so the pickers are not re-evaluated once a second.
private struct SessionEditRow: View {
    let engine: TimerEngine
    let session: Session

    @State private var draftProjectID: UUID
    @State private var draftStart: Date
    @State private var draftEnd: Date?
    @State private var message: String?
    @State private var isConfirmingDelete = false

    init(engine: TimerEngine, session: Session) {
        self.engine = engine
        self.session = session
        _draftProjectID = State(initialValue: session.projectID)
        _draftStart = State(initialValue: session.start)
        _draftEnd = State(initialValue: session.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(draftProject?.displayColor ?? Color.chronosScarlet)
                    .frame(width: 9, height: 9)

                Picker("Project", selection: $draftProjectID) {
                    ForEach(assignableProjects) { project in
                        Text(project.name).tag(project.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)

                Spacer(minLength: 0)

                durationLabel
            }

            HStack(spacing: 12) {
                DatePicker(
                    "Start",
                    selection: timeBinding(draftStart) { draftStart = $0 },
                    displayedComponents: .hourAndMinute
                )
                .frame(maxWidth: 150)

                if draftEnd == nil {
                    Text("Running")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Stop at…") { seedEnd() }
                } else {
                    DatePicker(
                        "End",
                        selection: timeBinding(draftEnd ?? draftStart) { draftEnd = $0 },
                        displayedComponents: .hourAndMinute
                    )
                    .frame(maxWidth: 150)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button("Save") { save() }
                    .disabled(!isDirty(against: session) || validationMessage != nil)
                Button("Revert") { resync(to: session) }
                    .disabled(!isDirty(against: session))
                Spacer(minLength: 0)
                Button("Delete", role: .destructive) { isConfirmingDelete = true }
            }

            if let caption = validationMessage ?? message {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .confirmationDialog(
            // `engine.clock.now()`, not `engine.now`: reading the ticking
            // property here would re-evaluate this whole body every second.
            "Delete this \(TimeFormatting.hms(session.duration(asOf: engine.clock.now()))) session?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The time comes off today's total. This cannot be undone.")
        }
        .onChange(of: session) { old, new in
            // The session changed underneath us — it was stopped from the
            // panel, say. An untouched row follows it; a row with unsaved
            // edits keeps them and lets Save report the conflict.
            guard !isDirty(against: old) else { return }
            resync(to: new)
        }
    }

    // MARK: - Drafts

    private var draftProject: Project? {
        engine.projects.first { $0.id == draftProjectID }
    }

    /// The panel's projects, plus an archived one when it is this session's own
    /// project or the draft's — a session must never lose the project it is
    /// actually on just because that project has been put away, and the picker
    /// must always carry a tag for what it is showing.
    private var assignableProjects: [Project] {
        engine.projects.filter {
            !$0.isArchived || $0.id == session.projectID || $0.id == draftProjectID
        }
    }

    private func isDirty(against session: Session) -> Bool {
        draftProjectID != session.projectID || draftStart != session.start || draftEnd != session.end
    }

    private func resync(to session: Session) {
        draftProjectID = session.projectID
        draftStart = session.start
        draftEnd = session.end
        message = nil
    }

    private var validationMessage: String? {
        SessionEditing.validationError(
            start: draftStart,
            end: draftEnd,
            isOpen: session.isOpen,
            dayStart: engine.lastRollover,
            now: engine.clock.now()
        )?.errorDescription
    }

    // MARK: - Bindings

    /// A `.hourAndMinute` picker only ever means a time of day; which instant
    /// that is inside the tracking day is ``SessionEditing/instant(hour:minute:reference:dayStart:dayEnd:calendar:)``'s
    /// job. `current` is both the value shown and the reference the picked time
    /// is resolved against. A time that does not occur in this tracking day
    /// leaves the draft where it was and says so.
    private func timeBinding(_ current: Date, assign: @escaping (Date) -> Void) -> Binding<Date> {
        Binding(
            get: { current },
            set: { picked in
                guard let resolved = resolve(picked, reference: current) else {
                    message = "That time is not in today's tracking day."
                    return
                }
                assign(resolved)
                message = nil
            }
        )
    }

    private func resolve(_ picked: Date, reference: Date) -> Date? {
        let calendar = engine.trackingCalendar
        let parts = calendar.dateComponents([.hour, .minute], from: picked)
        return SessionEditing.instant(
            hour: parts.hour ?? 0,
            minute: parts.minute ?? 0,
            reference: reference,
            dayStart: engine.lastRollover,
            // An overdue rollover — the boundary has passed but the scheduler
            // has not fired yet — must not make "now" unpickable. The engine's
            // own `endInFuture`/`notToday` checks still bound what Save accepts.
            dayEnd: max(engine.nextRolloverBoundary, engine.clock.now().addingTimeInterval(1)),
            calendar: calendar
        )
    }

    // MARK: - Duration

    @ViewBuilder
    private var durationLabel: some View {
        if let end = draftEnd {
            Text(TimeFormatting.hms(max(0, end.timeIntervalSince(draftStart))))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            RunningDurationLabel(engine: engine, start: draftStart)
        }
    }

    // MARK: - Actions

    /// "Stop at…" seeds the end with now and reveals the picker; nothing is
    /// written until Save, and Save goes through the same `editSession` path as
    /// every other correction (never a second `close` record).
    private func seedEnd() {
        draftEnd = max(draftStart, engine.clock.now())
        message = nil
    }

    private func save() {
        do {
            try engine.editSession(
                session.id,
                projectID: draftProjectID,
                start: draftStart,
                end: draftEnd
            )
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try engine.deleteSession(session.id)
        } catch {
            message = error.localizedDescription
        }
    }
}

/// The one thing in the editor that ticks: an open session's running total.
/// Kept to its own view so `engine.now` does not invalidate a body full of
/// `DatePicker`s every second.
private struct RunningDurationLabel: View {
    let engine: TimerEngine
    let start: Date

    var body: some View {
        Text(TimeFormatting.hms(max(0, engine.now.timeIntervalSince(start))))
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}
