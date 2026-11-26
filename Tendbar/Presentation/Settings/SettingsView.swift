import AppKit
import SwiftUI
import TendbarApplication
import TendbarDomain

enum SettingsPage: String, CaseIterable, Identifiable {
    case claudeCode, notifications, appearance, general

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .claudeCode: "Claude Code"
        case .notifications: "Notifications"
        case .appearance: "Appearance"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .claudeCode: "terminal"
        case .notifications: "bell"
        case .appearance: "macwindow"
        case .general: "gearshape"
        }
    }
}

/// Set while a settings page edits text in place, so Esc cancels that edit rather than closing the window.
struct EditingInPlaceKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var editingInPlace: Bool? {
        get { self[EditingInPlaceKey.self] }
        set { self[EditingInPlaceKey.self] = newValue }
    }
}

struct SettingsView: View {
    let container: AppContainer
    @State private var page: SettingsPage
    @FocusedValue(\.editingInPlace) private var editingInPlace

    init(container: AppContainer, page: SettingsPage = .claudeCode) {
        self.container = container
        _page = State(initialValue: page)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().ignoresSafeArea()
            detail
                .modifier(NoTopScrollEdge())
                .padding(.top, 12)
                .ignoresSafeArea(edges: .top)
        }
        .frame(width: 700, height: 500)
        .background(closeOnEscape)
        .unifiedTitleBar()
        .onAppear(perform: refresh)
    }

    /// Esc closes the window as well as ⌘W. An open picker menu takes Esc first, and while a page edits text in
    /// place (a new profile name) Esc belongs to that page's Cancel.
    private var closeOnEscape: some View {
        Button("Close") { NSApp.keyWindow?.performClose(nil) }
            .keyboardShortcut(.cancelAction)
            .disabled(editingInPlace == true)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                Text("Tendbar").font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 16)
            ForEach(SettingsPage.allCases) { item in
                Button { page = item } label: {
                    Label(item.title, systemImage: item.symbol)
                        .labelStyle(SidebarLabelStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(page == item ? Color.primary.opacity(0.08) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(page == item ? .primary : .secondary)
                .accessibilityAddTraits(page == item ? .isSelected : [])
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Button("Data folder") { container.systemActions.revealDataFolder() }
                Text(Self.version)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .buttonStyle(.link)
            .font(.caption)
            .padding(.horizontal, 6)
        }
        .padding(12)
        .frame(width: 188)
        .background(.regularMaterial, ignoresSafeAreaEdges: .all)
    }

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .claudeCode:
            ClaudeCodeSettings(model: container.claudeCode, actions: container.claudeCodeActions)
        case .notifications:
            NotificationSettings(preferences: container.preferences, model: container.system, actions: container.systemActions)
        case .appearance:
            AppearanceSettings(preferences: container.preferences)
        case .general:
            GeneralSettings(
                preferences: container.preferences,
                system: container.system,
                systemActions: container.systemActions,
                updates: container.updates,
                diagnostics: { [container] in Diagnostics.report(container) }
            )
        }
    }

    private static var version: String {
        String(localized: "Version \(AppVersion.label) (\(AppVersion.build))")
    }

    private func refresh() {
        container.claudeCodeActions.refresh()
        container.systemActions.refresh()
    }
}

private struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.frame(width: 18)
            configuration.title
        }
        .font(.system(size: 13, weight: .medium))
    }
}

private struct ClaudeCodeSettings: View {
    let model: ClaudeCodeViewModel
    let actions: ClaudeCodeController

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    switch model.connection {
                    case .connected:
                        Button("Disconnect") { actions.disconnect() }
                    case .outdated, .otherCopy, .helperGone:
                        HStack {
                            Button("Disconnect") { actions.disconnect() }
                            Button("Update") { actions.connect() }
                                .buttonStyle(.borderedProminent)
                        }
                    case .disconnected:
                        Button("Connect") { actions.connect() }
                            .buttonStyle(.borderedProminent)
                    case nil:
                        EmptyView()
                    }
                } label: {
                    HStack(spacing: 10) {
                        StatusDot(color: model.connection == .connected ? Palette.sage : Palette.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connectionText)
                            Text("Hooks in ~/.claude/settings.json")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                if let error = model.connectionError {
                    Text(error).foregroundStyle(Palette.vermilionText).textSelection(.enabled)
                } else {
                    Text("settings.json is backed up before every change")
                }
            }
            AccountsSection(model: model, actions: actions)
        }
        .formStyle(.grouped)
    }

    private var connectionText: String {
        switch model.connection {
        case .connected: String(localized: "Connected to Claude Code")
        case .outdated: String(localized: "Connection needs an update")
        case .otherCopy: String(localized: "Connected to another copy of Tendbar")
        case .helperGone: String(localized: "The hooks run a missing tendbar-hook")
        case .disconnected: String(localized: "Not connected")
        case nil: String(localized: "tendbar-hook missing")
        }
    }
}

/// A shortcut from the Shortcuts app per event, run by `ShortcutTrigger` along with the notification.
private struct EventShortcutsSection: View {
    @Bindable var preferences: Preferences
    @State private var names: [String] = []

    var body: some View {
        Section {
            picker("A session waits for you", event: AlertKind.needsYou.rawValue)
            picker("A session finishes", event: AlertKind.done.rawValue)
            picker("A turn fails", event: AlertKind.failed.rawValue)
            picker("An account passes 80% and 90% of a limit", event: ShortcutTrigger.limitKey)
        } header: {
            Text("Run a shortcut when")
        } footer: {
            Text("The shortcut runs along with the notification, so that notification has to be on")
        }
        .task { names = await ShortcutTrigger.names() }
    }

    private func picker(_ title: LocalizedStringKey, event: String) -> some View {
        let chosen = preferences.eventShortcuts[event]
        return Picker(title, selection: Binding(
            get: { chosen ?? "" },
            set: { preferences.eventShortcuts[event] = $0.isEmpty ? nil : $0 }
        )) {
            Text("None").tag("")
            ForEach(names, id: \.self) { Text($0).tag($0) }
            // A shortcut renamed or deleted since keeps its row, so the choice stays visible.
            if let chosen, !names.contains(chosen) { Text(chosen).tag(chosen) }
        }
    }
}

private struct NotificationSettings: View {
    @Bindable var preferences: Preferences
    let model: SystemViewModel
    let actions: SystemController
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Toggle("A session waits for you", isOn: $preferences.notifyNeedsYou)
                Toggle("Allow and Deny for permission prompts", isOn: $preferences.permissionActions)
                    .disabled(!preferences.notifyNeedsYou)
                    .padding(.leading, 16)
                Toggle("A session finishes", isOn: $preferences.notifyDone)
                Toggle("Start of the reply in “Done” notifications", isOn: $preferences.showReplyPreview)
                    .disabled(!preferences.notifyDone)
                    .padding(.leading, 16)
                Toggle("A turn fails", isOn: $preferences.notifyFailed)
                Toggle(isOn: $preferences.glowOnlyInFront) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only a glow when the session is in front")
                        Text("No banner or sound while you look at the session's tab. A reminder still comes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: Binding(get: { !preferences.leaveDesktopBanners }, set: { preferences.leaveDesktopBanners = !$0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notify about Claude app sessions too")
                        if preferences.leaveDesktopBanners {
                            Text("The Claude desktop app notifies and asks for permission itself. The screen edge still glows")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !preferences.leaveDesktopBanners {
                    // macOS lets no app turn off another app's notifications, so Tendbar opens the right pane instead.
                    LabeledContent {
                        Button("Claude Notifications…") { actions.openNotificationSettings(bundleID: TerminalContext.claudeDesktopBundleID) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Turn off Claude's own notifications")
                            Text("Otherwise each event gives two banners: one from Claude and one from Tendbar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 16)
                }
            } header: {
                Text("Notify when")
            } footer: {
                Text("Allow and Deny appear on the notification, in the panel and in the pill, under the whole command or file. A request that doesn't fit gets Deny only, and you allow it in the terminal. The terminal prompt keeps working, and whichever you answer first decides. Your deny rules still apply")
            }
            Section {
                Picker("Remind about a wait after", selection: $preferences.remindAfterMinutes) {
                    minutes([2, 5, 10, 15])
                }
                .disabled(!preferences.notifyNeedsYou)
                Picker("Flag a quiet session after", selection: $preferences.quietAfterMinutes) {
                    minutes([10, 15, 30])
                }
                Toggle("An account passes 80% and 90% of a limit", isOn: $preferences.notifyLimits)
                Toggle("That limit is available again", isOn: $preferences.notifyLimitResets)
                    .disabled(!preferences.notifyLimits)
                    .padding(.leading, 16)
            } header: {
                Text("Follow up")
            } footer: {
                Text("A reminder comes once per wait. A session that works with no sign of life for that long may hang on a command or a dropped connection")
            }
            Section {
                Toggle("Sound", isOn: $preferences.playSound)
                Picker("Sound style", selection: $preferences.soundStyle) {
                    Text("Bird calls").tag(SoundStyle.bird)
                    Text("System sound").tag(SoundStyle.system)
                }
                .disabled(!preferences.playSound)
                // "Test notification" below plays the bird call at this volume.
                Slider(value: $preferences.soundVolume, in: 0.1...1) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill").accessibilityHidden(true)
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
                }
                .disabled(!preferences.playSound || preferences.soundStyle != .bird)
                .help(preferences.soundStyle == .bird ? "" : "The system sound plays at the system volume")
                Toggle("Glowing screen edge", isOn: $preferences.edgeGlow)
                Toggle("Glow when a session finishes too", isOn: $preferences.glowOnDone)
                    .disabled(!preferences.edgeGlow)
                    .padding(.leading, 16)
                LabeledContent {
                    Button("Focus Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") { openURL(url) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("During a Focus")
                        Text("Add Tendbar's filter to a Focus to turn off its sounds and glow while the Focus is on")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent {
                    HStack {
                        Button("Preview glow") { actions.showFlash() }
                        Button("Test notification") { actions.sendTestNotification() }
                    }
                } label: {
                    Text("Try it")
                }
            } header: {
                Text("How")
            } footer: {
                Text("The edge glows orange when a session waits, green when it finishes, red after an error and at 90% of a limit. Right-click a session in the panel to mute its folder")
            }
            EventShortcutsSection(preferences: preferences)
            if !preferences.mutedFolders.isEmpty {
                Section {
                    ForEach(preferences.mutedFolders, id: \.self) { folder in
                        LabeledContent {
                            Button("Unmute") { preferences.setMuted(false, folder: folder) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(URL(fileURLWithPath: folder).lastPathComponent)
                                Text(folder)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                        }
                    }
                } header: {
                    Text("Muted folders")
                } footer: {
                    Text("Sessions in these folders still show in the panel, without banners or glow")
                }
            }
            if !granted || model.notificationError != nil {
                Section {
                    if !granted {
                        LabeledContent {
                            HStack {
                                if model.notificationPermission == .notDetermined {
                                    Button("Ask for permission") { actions.requestNotifications() }
                                }
                                Button("System Settings") { actions.openNotificationSettings() }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                StatusDot(color: Palette.amber)
                                Text(model.notificationPermission == .notDetermined
                                    ? String(localized: "macOS has not asked for permission yet")
                                    : String(localized: "Notifications are turned off in macOS"))
                            }
                        }
                    }
                    if let error = model.notificationError {
                        Text(error).foregroundStyle(Palette.vermilionText).textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            actions.refresh()
        }
        // Allowing from the macOS prompt does not activate Tendbar, so check again until the permission arrives.
        .task(id: granted) {
            while !granted, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await actions.refreshNotifications()
            }
        }
    }

    private var granted: Bool {
        model.notificationPermission == .authorized
    }

    @ViewBuilder
    private func minutes(_ choices: [Int]) -> some View {
        Text("Off").tag(0)
        ForEach(choices, id: \.self) { minutes in
            Text("\(minutes) min").tag(minutes)
        }
    }

}

private struct AppearanceSettings: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $preferences.theme) {
                    Text("System").tag(Theme.system)
                    Text("Light").tag(Theme.light)
                    Text("Dark").tag(Theme.dark)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("For the panel and settings. The pill stays dark next to the notch")
            }
            Section("Menu bar") {
                Picker("Next to the bird", selection: $preferences.menuBarStyle) {
                    Text("Nothing").tag(MenuBarStyle.bird)
                    Text("Sessions waiting for you").tag(MenuBarStyle.waiting)
                    Text("Highest limit").tag(MenuBarStyle.limit)
                }
            }
            Section {
                Toggle(NotchController.hasNotch ? "Pill next to the notch" : "Pill in the middle of the menu bar", isOn: $preferences.notchView)
            } header: {
                Text("Pill")
            } footer: {
                Text("Hover the pill to see the sessions and every account's limits")
            }
            Section("Panel") {
                Toggle("Start of the reply under each session", isOn: $preferences.panelPreviews)
                Toggle("Today's turns and waits", isOn: $preferences.panelToday)
                Picker("Usage limits", selection: $preferences.usageStyle) {
                    Text("Full").tag(UsageStyle.full)
                    Text("Compact").tag(UsageStyle.compact)
                    Text("Hidden").tag(UsageStyle.hidden)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSettings: View {
    @Bindable var preferences: Preferences
    let system: SystemViewModel
    let systemActions: SystemController
    @Bindable var updates: SoftwareUpdate
    let diagnostics: () -> String
    @State private var language = AppLanguage.current
    @State private var copied = false
    @State private var copies = 0
    @State private var asksRestart = false

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { system.loginItem != .disabled },
                    set: { systemActions.setLaunchAtLogin($0) }
                ))
                Toggle(isOn: $preferences.hideFromCapture) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide from screen sharing")
                        Text("The pill and the glow stay off shared screens and recordings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $preferences.logEvents) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Event log")
                            Text("For troubleshooting. Turning it off deletes the log")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if preferences.logEvents {
                            Button("Show") { systemActions.revealEventLog() }
                        }
                    }
                }
            } footer: {
                if system.loginItem == .requiresApproval {
                    Text("Allow Tendbar in System Settings → General → Login Items")
                        .foregroundStyle(.secondary)
                } else if let error = system.loginItemError {
                    Text(error).foregroundStyle(Palette.vermilionText)
                } else {
                    Text("Everything stays on this Mac. Only the update check reaches the network")
                }
            }
            Section {
                Picker(selection: $preferences.nextSessionShortcut) {
                    Text("Off").tag(NextSessionShortcut.off)
                    ForEach(NextSessionShortcut.allCases.filter { $0 != .off }) { shortcut in
                        Text(verbatim: shortcut.symbols ?? "").tag(shortcut)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shortcut to the next session")
                        Text("From any app, to the session waiting longest, then to unread replies")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if system.shortcutTaken {
                    Text("Another app already uses this shortcut. Pick another one")
                        .foregroundStyle(Palette.vermilion)
                }
            }
            Section {
                LabeledContent {
                    Button(copied ? String(localized: "Copied") : String(localized: "Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diagnostics(), forType: .string)
                        copied = true
                        copies += 1
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostics for a bug report")
                        Text("Versions, terminals and settings. No folder names, e-mails or messages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if updates.isAvailable {
                Section {
                    Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
                    Toggle("Receive beta versions", isOn: $updates.receivesBetas)
                    Button("Check Now") { updates.checkNow() }
                } header: {
                    Text("Updates")
                } footer: {
                    Text("Once a day Tendbar reads the list of releases on GitHub. Nothing about you or your sessions is sent. Betas bring new features first and may have rough edges")
                }
            }
            Section {
                Picker("Language", selection: $language) {
                    Text("System").tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "Polski").tag(AppLanguage.polish)
                }
                .onChange(of: language) {
                    language.apply()
                    asksRestart = language != AppLanguage.launched
                }
                if language != AppLanguage.launched {
                    LabeledContent("Takes effect after a restart") {
                        Button("Restart Tendbar") { AppLanguage.relaunch() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task(id: copies) {
            guard copies > 0, (try? await Task.sleep(for: .seconds(2))) != nil else { return }
            copied = false
        }
        .alert("Restart Tendbar now?", isPresented: $asksRestart) {
            Button("Restart") { AppLanguage.relaunch() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The new language shows after a restart")
        }
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
    }
}

/// The hidden title bar has nothing to separate, so the scroll edge effect would only draw a band over the first
/// section.
private struct NoTopScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollEdgeEffectHidden(true, for: .top)
    }
}
