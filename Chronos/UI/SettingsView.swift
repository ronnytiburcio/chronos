import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The settings window's content (SPEC §8, "Settings window"): every stored
/// preference, the project list, and the CSV export.
///
/// Unlike the panel this is an ordinary window, so it takes the system
/// appearance and system control styling rather than the Ink/Paper palette —
/// the only Chronos colors here are the project swatches.
///
/// Every mutation goes through ``TimerEngine``, which is still the single
/// writer of `state.json`. Changing the rollover time additionally calls
/// `onRolloverChanged`, because an armed ``RolloverScheduler`` timer keeps its
/// old fire date until something re-arms it.
struct SettingsView: View {
    let engine: TimerEngine
    /// Called after `settings.rollover` changes. The app delegate re-arms the
    /// rollover scheduler with it.
    var onRolloverChanged: () -> Void = {}

    /// Which of SPEC §8's three ranges the Export button uses.
    private enum RangeChoice: String, CaseIterable, Identifiable {
        case thisWeek, thisMonth, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .thisWeek: "This week"
            case .thisMonth: "This month"
            case .custom: "Custom"
            }
        }
    }

    @State private var rangeChoice: RangeChoice = .thisWeek
    @State private var customFrom = Date()
    @State private var customTo = Date()
    @State private var exportMessage: String?
    @State private var exportError: String?
    /// The login item's real state, which lives in macOS rather than in
    /// `state.json` and so has to be re-read rather than observed.
    @State private var loginItemNeedsApproval = false
    @State private var loginItemError: String?

    var body: some View {
        Form {
            trackingSection
            archiveSection
            startupSection
            projectsSection
            exportSection
            footer
        }
        .formStyle(.grouped)
        .frame(minWidth: SettingsWindowController.contentSize.width, minHeight: 0)
        .onAppear {
            loginItemNeedsApproval = LoginItem.requiresApproval
            let bounds = engine.exportBounds(for: .thisWeek)
            customFrom = day(bounds.from) ?? engine.now
            customTo = day(bounds.to) ?? engine.now
        }
    }

    // MARK: - Tracking

    private var trackingSection: some View {
        Section("Tracking") {
            DatePicker(
                "Rollover time",
                selection: rolloverBinding,
                displayedComponents: .hourAndMinute
            )
            Text("The tracking day runs from one rollover to the next, so late-night work stays on the day it belongs to.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Restart running project after rollover", isOn: setting(\.restartRunningProjectAfterRollover))
        }
    }

    /// The stored ``RolloverTime`` as a `Date`, which is what `DatePicker`
    /// speaks. The day the time is pinned to is arbitrary and never leaves this
    /// binding; only the hour and minute are read back out.
    private var rolloverBinding: Binding<Date> {
        Binding(
            get: {
                let rollover = engine.settings.rollover
                var components = DateComponents()
                components.year = 2001
                components.month = 1
                components.day = 1
                components.hour = rollover.hour
                components.minute = rollover.minute
                return engine.trackingCalendar.date(from: components) ?? engine.now
            },
            set: { date in
                let parts = engine.trackingCalendar.dateComponents([.hour, .minute], from: date)
                let updated = RolloverTime(hour: parts.hour ?? 4, minute: parts.minute ?? 0)
                guard updated != engine.settings.rollover else { return }
                engine.updateSettings { $0.rollover = updated }
                onRolloverChanged()
            }
        )
    }

    // MARK: - Archive

    private var archiveSection: some View {
        Section("Archive") {
            LabeledContent("Folder") {
                Text(archiveFolder.path)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(archiveFolder.path)
            }
            HStack {
                Button("Choose…") { chooseArchiveFolder() }
                Button("Use Default") {
                    engine.updateSettings { $0.archiveFolderPath = nil }
                }
                .disabled(engine.settings.archiveFolderPath == nil)
            }
            Toggle("Write markdown daily notes", isOn: setting(\.writeMarkdownDailyNotes))
        }
    }

    private var archiveFolder: URL {
        AppPaths.archiveDirectory(forSettingsPath: engine.settings.archiveFolderPath)
    }

    private func chooseArchiveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = archiveFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Stored `~`-relative when it is inside the home folder, so a renamed
        // home (or a restored backup) does not strand the archive.
        let path = (url.path as NSString).abbreviatingWithTildeInPath
        engine.updateSettings { $0.archiveFolderPath = path }
    }

    // MARK: - Menu bar & startup

    private var startupSection: some View {
        Section("Menu bar & startup") {
            Toggle("Show elapsed time in menu bar", isOn: setting(\.showElapsedInMenuBar))
            Toggle("Launch at login", isOn: launchAtLoginBinding)
            if loginItemNeedsApproval {
                Text("Approve Chronos in System Settings › General › Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    /// Writes the user's intent to `state.json` either way, and reports a
    /// refused registration inline — never as an alert, which would drag the
    /// user out of the window they are already looking at.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { engine.settings.launchAtLogin },
            set: { wanted in
                loginItemError = nil
                do {
                    try LoginItem.setEnabled(wanted)
                } catch {
                    loginItemError = "Could not \(wanted ? "enable" : "disable") launch at login: \(error.localizedDescription)"
                }
                loginItemNeedsApproval = LoginItem.requiresApproval
                engine.updateSettings { $0.launchAtLogin = wanted }
            }
        )
    }

    // MARK: - Projects

    private var projectsSection: some View {
        Section("Projects") {
            if engine.projects.isEmpty {
                Text("No projects yet. Add your first one in the panel.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(engine.visibleProjects.enumerated()), id: \.element.id) { index, project in
                row(for: project, canMoveUp: index > 0, canMoveDown: index < engine.visibleProjects.count - 1)
            }
            if !engine.archivedProjects.isEmpty {
                Text("Archived")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(engine.archivedProjects) { project in
                    row(for: project, canMoveUp: false, canMoveDown: false)
                }
            }
        }
    }

    private func row(for project: Project, canMoveUp: Bool, canMoveDown: Bool) -> some View {
        ProjectSettingsRow(
            project: project,
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            onRename: { engine.renameProject(project.id, to: $0) },
            onSetColor: { engine.setColor($0, for: project.id) },
            onMove: { engine.moveProject(project.id, direction: $0) },
            onToggleArchive: {
                if project.isArchived {
                    engine.unarchiveProject(project.id)
                } else {
                    engine.archiveProject(project.id)
                }
            }
        )
    }

    // MARK: - Export

    private var exportSection: some View {
        Section("Export") {
            Picker("Range", selection: $rangeChoice) {
                ForEach(RangeChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            if rangeChoice == .custom {
                DatePicker("From", selection: $customFrom, displayedComponents: .date)
                DatePicker("To", selection: $customTo, displayedComponents: .date)
            }

            HStack {
                Button("Export CSV…") { export() }
                Spacer()
                Text(exportRangeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let exportMessage {
                Text(exportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var resolvedRange: ExportRange {
        switch rangeChoice {
        case .thisWeek: .thisWeek
        case .thisMonth: .thisMonth
        case .custom: .custom(from: customFrom, to: customTo)
        }
    }

    private var exportRangeLabel: String {
        let bounds = engine.exportBounds(for: resolvedRange)
        return bounds.from == bounds.to ? bounds.from : "\(bounds.from) → \(bounds.to)"
    }

    private func export() {
        exportMessage = nil
        exportError = nil

        // Resolved once and used for both the rows and the file name, so the
        // two can never describe different ranges.
        let bounds = engine.exportBounds(for: resolvedRange)
        let text: String
        do {
            text = try engine.exportCSV(from: bounds.from, to: bounds.to)
        } catch {
            exportError = "Could not read the session history: \(error.localizedDescription)"
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = Exporter.fileName(from: bounds.from, to: bounds.to)
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            exportMessage = "Saved to \(url.path)"
        } catch {
            exportError = "Could not write \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// A `yyyy-MM-dd` day string back as a `Date`, for seeding the custom
    /// pickers with the current week.
    private func day(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return engine.trackingCalendar.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        Section {
            LabeledContent("Version") {
                Text("\(AppInfo.name) \(AppInfo.version)")
                    .textSelection(.enabled)
            }
            LabeledContent("Data") {
                Text(AppPaths.appSupportDirectory.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(AppPaths.appSupportDirectory.path)
            }
        }
    }

    // MARK: - Bindings

    /// A two-way binding onto one stored setting, writing through the engine so
    /// `state.json` keeps its single writer.
    private func setting<Value: Equatable>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(
            get: { engine.settings[keyPath: keyPath] },
            set: { value in engine.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }
}

/// One project in Settings' list: rename, recolor, reorder, archive.
///
/// The name is edited in a local draft and committed on Return or when the
/// field gives up focus, rather than on every keystroke — the engine ignores a
/// blank rename, so a per-keystroke binding would fight the user the moment
/// they select-all and start typing.
private struct ProjectSettingsRow: View {
    let project: Project
    let canMoveUp: Bool
    let canMoveDown: Bool
    var onRename: (String) -> Void
    var onSetColor: (String?) -> Void
    var onMove: (MoveDirection) -> Void
    var onToggleArchive: () -> Void

    @State private var draftName: String
    @FocusState private var isEditing: Bool

    init(
        project: Project,
        canMoveUp: Bool,
        canMoveDown: Bool,
        onRename: @escaping (String) -> Void,
        onSetColor: @escaping (String?) -> Void,
        onMove: @escaping (MoveDirection) -> Void,
        onToggleArchive: @escaping () -> Void
    ) {
        self.project = project
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.onRename = onRename
        self.onSetColor = onSetColor
        self.onMove = onMove
        self.onToggleArchive = onToggleArchive
        _draftName = State(initialValue: project.name)
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                // A `Form` would otherwise stack its own "Name" label above
                // the field and right-align the text inside it.
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .frame(minWidth: 120)
                .focused($isEditing)
                .onSubmit { commit() }
                .onChange(of: isEditing) { _, editing in
                    if !editing { commit() }
                }

            Picker("Color", selection: colorBinding) {
                ForEach(ProjectColorOptions.all) { option in
                    HStack {
                        Circle()
                            .fill(option.color)
                            .frame(width: 9, height: 9)
                        Text(option.name)
                    }
                    .tag(option.hex as String?)
                }
            }
            .labelsHidden()
            .frame(width: 110)

            Button { onMove(.up) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(!canMoveUp)
            .help("Move up")

            Button { onMove(.down) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(!canMoveDown)
            .help("Move down")

            Button(project.isArchived ? "Unarchive" : "Archive", action: onToggleArchive)
        }
        .onChange(of: project.name) { _, name in
            // A rename from somewhere else (the panel's row menu) while this
            // field is idle should show up here too.
            if !isEditing { draftName = name }
        }
    }

    private var colorBinding: Binding<String?> {
        Binding(get: { project.colorHex }, set: { hex in onSetColor(hex) })
    }

    private func commit() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // The engine refuses a blank name; put the real one back rather
            // than leaving an empty field lying about what is stored.
            draftName = project.name
            return
        }
        guard trimmed != project.name else { return }
        onRename(trimmed)
    }
}
