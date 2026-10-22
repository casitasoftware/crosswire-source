//
//  ContentView.swift
//  Crosswire
//
//  This file is part of Crosswire.
//
//  Crosswire is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Crosswire is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Crosswire.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import AppKit
import CrosswireKit
import SemanticVersion
import Sparkle

// swiftlint:disable type_body_length file_length
struct ContentView: View {
    @AppStorage("checkEngineUpdates") var checkEngineUpdates = true
    @EnvironmentObject var bottleVM: BottleVM
    @Binding var showSetup: Bool
    let sparkleUpdater: SPUUpdater?

    @State var bottlesLoaded: Bool = false
    @State var searchText: String = ""
    @State var openedFileURL: URL?
    @State var setupStartingStage: SetupStage?
    /// Forced engine reinstall (channel switch, accept an update prompt):
    /// presents EngineSetupView directly, bypassing SetupView/WelcomeView's
    /// path-based navigation entirely. That path relies on
    /// `setupStartingStage` still holding `.engineSetup` by the time
    /// `.sheet`'s content closure constructs SetupView, which in practice
    /// (confirmed via dogfooding a Stage-2 bundle-only install) does not
    /// reliably happen -- the sheet ends up showing WelcomeView's root
    /// instead, with the reinstall never actually starting. This dedicated
    /// sheet has nothing to race: it is armed and torn down by the same
    /// single Bool.
    @State var showForceEngineReinstall = false
    @State var forceReinstallPath: [SetupStage] = []
    /// Startup prompts, presented as SwiftUI alerts rather than
    /// `NSAlert.runModal()`: `onAppearTask` runs on the main actor, and a modal
    /// loop there blocks the main queue until the user answers (CROSSWIRE-13).
    @State var showConsentPrompt = false
    /// Body text of the pending "engine update available" prompt; nil = none.
    @State var engineUpdateMessage: String?
    @State var showEngineUpdateAlert = false

    /// Top-level navigation. Library is the default; Settings + per-entry
    /// detail are full-bleed inline destinations that slide in over the
    /// library view. See `AppRoute` for the full rationale.
    @State var route: AppRoute = .library

    @State var provisioningMessage: String?
    /// True while an install NSOpenPanel is open but not yet resolved.
    /// provisioningMessage alone doesn't guard this window — it's only set
    /// once a file is actually picked, so nothing previously stopped a second
    /// picker from opening while the first still sat unpicked (confirmed live
    /// while investigating #120: two, even three, pickers could stack).
    @State var installPickerOpen = false
    @State var runtimesPrompt: RuntimesPrompt?
    @State var dropTargeted: Bool = false
    @StateObject private var selection = LibrarySelection()
    /// Set while waiting for an installer to exit; non-nil drives the overlay's
    /// "Finish Setup" escape hatch so a portable GUI app (which never exits)
    /// can't trap the UI on "Running installer…". See `waitForInstallerOrFinish`.
    @State var installerEscape: InstallerEscape?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @State private var emptyHeroAppeared = false

    init(showSetup: Binding<Bool>, sparkleUpdater: SPUUpdater? = nil) {
        self._showSetup = showSetup
        self.sparkleUpdater = sparkleUpdater
    }

    var body: some View {
        ZStack {
            // Library is the always-present base layer. Settings + per-entry
            // detail overlay it with slide-in transitions. Library doesn't
            // animate out — the overlay just covers it.
            libraryRoot

            if case let .entryDetail(id) = route,
               let bottle = bottleVM.bottles.first(where: { $0.id == id }) {
                EntryDetailView(
                    bottle: bottle,
                    onBack: { withAnimation(CrosswireTheme.Motion.navigation) { route = .library } },
                    onRun: { runPrimary(for: bottle) },
                    onRunProgram: { program in run(program: program, bottle: bottle) },
                    onUninstall: { uninstall(bottle) },
                    onLaunchDiagnostics: { runWithDiagnostics(for: bottle) }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CrosswireTheme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Crosswire")
        // The window keeps its name for Mission Control and the Window menu,
        // but the toolbar shows "Library" and the app count instead: the
        // window's own name told the user nothing they did not know. Removing
        // the toolbar title outright needs macOS 15, and the deployment
        // target is 14.6, so it is hidden rather than removed.
        .modifier(HiddenToolbarTitle())
        .toolbar { crosswireToolbar }
        // Search trails the rest of the toolbar, which is where macOS 26 puts
        // it. It used to be drawn inside the library, once per view mode, so
        // there were two copies to keep in step and neither looked like a
        // toolbar search field.
        .searchable(text: $searchText,
                    placement: .toolbar,
                    prompt: Text("library.search.prompt"))
        .sheet(item: $openedFileURL) { url in
            FileOpenView(fileURL: url,
                         currentBottle: nil,
                         bottles: bottleVM.bottles)
        }
        .sheet(item: $runtimesPrompt) { prompt in
            DetectedRuntimesSheet(
                exeName: prompt.exeName,
                detected: prompt.detected,
                bottle: prompt.bottle
            ) { installed in
                prompt.continuation.resume(returning: installed)
                runtimesPrompt = nil
            }
        }
        .sheet(isPresented: $showSetup, onDismiss: { setupStartingStage = nil }, content: {
            SetupView(startingStage: setupStartingStage, showSetup: $showSetup, firstTime: false)
        })
        .sheet(isPresented: $showForceEngineReinstall) {
            EngineSetupView(path: $forceReinstallPath, showSetup: $showForceEngineReinstall)
        }
        .modifier(StartupAlerts(showConsentPrompt: $showConsentPrompt,
                                showEngineUpdateAlert: $showEngineUpdateAlert,
                                engineUpdateMessage: engineUpdateMessage,
                                onConsent: { mode in recordConsent(mode) },
                                onEngineUpdate: { acceptEngineUpdate() },
                                onEngineUpdateCancel: { engineUpdateMessage = nil }))
        .overlay {
            if let message = provisioningMessage {
                ProvisioningOverlay(message: message, escape: installerEscape)
            }
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            openedFileURL = url
        }
        .task {
            await onAppearTask()
        }
        // Reconciles the selection against installs/removals that happen
        // outside `uninstall(_:)` (a fresh install completing, a bottle
        // vanishing on disk). `uninstall(_:)` already reconciles explicitly
        // with the neighbor-selection rule; this is the general-purpose net.
        .onChange(of: bottleVM.bottles) { _, bottles in
            let sorted = bottles.sorted()
            if selection.selectedID == nil {
                selection.seed(from: sorted)
            } else {
                selection.reconcile(with: sorted)
            }
        }
        // Channel switch (Settings → Updates): the user already confirmed the
        // ~200 MB re-download, so swap the engine for the new channel by removing
        // the installed one and re-running setup (the manifest is channel-aware).
        .onReceive(NotificationCenter.default.publisher(for: .crosswireReprovisionEngine)) { _ in
            CrosswireEngine.uninstall()
            showForceEngineReinstall = true
        }
        // The welcome screen's "Choose an Installer…". The short delay lets the
        // setup sheet finish closing so the file picker does not open under it.
        .onReceive(NotificationCenter.default.publisher(for: .crosswireChooseInstaller)) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                installWindowsApp()
            }
        }
        .focusedSceneValue(\.libraryMenuActions, libraryMenuActions)
    }

    // MARK: - Library root (composes header + action row + content)

    /// The library view as a single composed surface. Sits at the base of
    /// the ZStack; the Settings (and per-entry, Section 2) overlays slide
    /// in over it. Extracted as its own var so the body-level ZStack stays
    /// readable.
    private var libraryRoot: some View {
        VStack(spacing: 0) {
            content
        }
        // Drop a Windows installer/executable anywhere on the library to start
        // the same install flow as the "Install" button (the empty state
        // invites exactly this). A faint accent border confirms the target.
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(of: urls)
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CrosswireTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .padding(12)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(CrosswireTheme.Motion.hover, value: dropTargeted)
    }

    // MARK: - Toolbar (native unified, replaces the old custom header)

    /// Native unified toolbar. Leading: the inline window title, set via
    /// `.navigationTitle` — plain text, not a control. Trailing: the settings
    /// gear, then the prominent blue "+" install button (the primary action).
    ///
    /// There is deliberately no brand menu here. About, Check for Updates and
    /// Quit all live in the macOS app menu already — About via
    /// `CommandGroup(replacing: .appInfo)` and updates via the `SparkleView`
    /// command group, both in `CrosswireApp` — so a toolbar menu carrying the
    /// same four items was duplicating the system menu bar.
    @ToolbarContentBuilder
    private var crosswireToolbar: some ToolbarContent {
        // Grid vs Sidebar. Meaningless (and hidden) with an empty library —
        // `emptyState` renders in place of the container then, so there is
        // nothing for it to switch between.
        if !bottleVM.bottles.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                LibraryViewModeSwitcher()
            }
        }

        // Settings gear sits just left of the prominent install CTA (split into
        // its own item below) so a group gap separates the secondary action
        // from the primary one. All actions belong on the trailing side.
        ToolbarItem(placement: .primaryAction) {
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            // No keyboard shortcut here: the Settings scene already owns Cmd+,
            // and declaring it twice makes the menu item stop working.
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }

        // Labeled "+ Install" (not a bare icon) — install is the app's primary
        // action and discoverability wins over toolbar minimalism. Its own item
        // so a group gap separates it from the secondary cluster; trailing
        // padding keeps it off the window edge. Suppressed when the library is
        // empty (the centered hero CTA is the single target there).
        if !bottleVM.bottles.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button(action: installWindowsApp) {
                    Label("Install App", systemImage: "plus")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .tint(CrosswireTheme.controlFill)
                .help("Install a Windows app (⌘N)")
                .accessibilityLabel("Install App")
                .padding(.trailing, 6)
            }
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if !bottlesLoaded {
            loadingState
        } else if bottleVM.bottles.isEmpty {
            emptyState
        } else {
            LibraryContainerView(
                bottles: filteredSort,
                searchText: $searchText,
                selection: selection,
                actions: bottleActions,
                // Return or a double-click opens the app itself. It used to
                // push the full-width detail route, which is what the
                // inspector replaces: looking at an app no longer means
                // losing sight of the library.
                onOpen: { bottle in
                    selection.select(bottle)
                    bottleActions.bound(to: bottle).run()
                },
                onAdd: installWindowsApp
            )
        }
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// The `BottleActions` bundle every library view (grid tile, sidebar row,
    /// detail pane) drives its context menu and Play control through. One
    /// value routes back out through the same run helpers `ContentView`
    /// already used, so single-instance handling applies uniformly no matter
    /// which view triggered it.
    private var bottleActions: BottleActions {
        BottleActions(
            run: { runPrimary(for: $0) },
            runProgram: { bottle, program in run(program: program, bottle: bottle) },
            uninstall: { uninstall($0) },
            launchDiagnostics: { runWithDiagnostics(for: $0) }
        )
    }

    /// What File > Install App… and File > Open do for this window. Open is nil
    /// when nothing is selected or the selected entry is gone.
    private var libraryMenuActions: LibraryMenuActions {
        let selected = bottleVM.bottles.first { $0.id == selection.selectedID }
        return LibraryMenuActions(
            install: installWindowsApp,
            openSelected: selected.map { bottle in { bottleActions.bound(to: bottle).run() } }
        )
    }

    /// First-launch / empty-library state. Uses the app's own icon (single
    /// source of truth — if the icon changes, so does this view), the
    /// brand tagline, and the same blue CTA that drives the action row.
    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 128, height: 128)
                .scaleEffect(emptyHeroAppeared ? 1 : 0.92)
                .opacity(emptyHeroAppeared ? 1 : 0)
                .shadow(color: CrosswireTheme.accent.opacity(emptyHeroAppeared ? 0.25 : 0),
                        radius: 24, x: 0, y: 8)
                .onAppear {
                    guard !reduceMotion else { emptyHeroAppeared = true; return }
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) {
                        emptyHeroAppeared = true
                    }
                }
            VStack(spacing: 8) {
                Text("No apps yet.")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CrosswireTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Choose a Windows installer, or drag one into this window.")
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: installWindowsApp) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("Install App")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(PrimaryCTAButtonStyle(size: .prominent))
            .padding(.top, 4)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Derived

    /// Sorted, unfiltered. Search narrowing happens inside
    /// `LibraryContainerView` per mode, since Sidebar mode needs the full list
    /// to keep resolving the selected bottle even when search has filtered it
    /// out of the visible rail.
    var filteredSort: [Bottle] {
        bottleVM.bottles.sorted()
    }

    // MARK: - Lifecycle

    @MainActor
    private func onAppearTask() async {
        bottleVM.loadBottles()
        bottlesLoaded = true
        selection.seed(from: filteredSort)

        if !CrosswireEngine.isEnginePresent() {
            setupStartingStage = nil
            showSetup = true
            return
        }

        // First-run: ask once whether to send crash reports (opt-in, nothing sent
        // until the user chooses). No-op after the first answer. Presented via
        // SwiftUI state, never `runModal()`, so this task doesn't block the main
        // actor while the prompt is open (CROSSWIRE-13).
        if CrosswireTelemetry.needsConsentPrompt() {
            showConsentPrompt = true
        }

        let updateInfo = await CrosswireEngine.shouldUpdateEngine()
        guard checkEngineUpdates, updateInfo.0 else { return }

        engineUpdateMessage = String(format: String(localized: "update.engine.description"),
                                     String(CrosswireEngine.engineVersion()
                                            ?? SemanticVersion(0, 0, 0)),
                                     String(updateInfo.1))
        // Only one alert can be up at a time; if the consent prompt is still
        // open, `recordConsent` shows the update prompt once it is answered.
        if !showConsentPrompt {
            showEngineUpdateAlert = true
        }
    }

    /// Records the first-run crash-reporting choice, then surfaces any engine
    /// update prompt that was held back while the consent alert was open.
    @MainActor
    private func recordConsent(_ mode: CrosswireTelemetry.CrashReportingMode) {
        CrosswireTelemetry.mode = mode
        guard engineUpdateMessage != nil else { return }
        // The short delay lets the consent alert finish dismissing; presenting a
        // second alert mid-dismissal can be silently dropped by SwiftUI.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            showEngineUpdateAlert = true
        }
    }

    /// "Update" on the engine update prompt: remove the installed engine and
    /// re-run engine setup.
    @MainActor
    private func acceptEngineUpdate() {
        engineUpdateMessage = nil
        CrosswireEngine.uninstall()
        showForceEngineReinstall = true
    }

    /// Confirm + remove an entry from the library (context-menu "Uninstall…").
    /// Deletes the bottle's files, drops it from the persisted path list, and
    /// reloads. Mirrors the per-app sheet's delete so both entry points behave
    /// identically.
    @MainActor
    private func uninstall(_ bottle: Bottle) {
        let alert = NSAlert()
        alert.messageText = "Uninstall \(bottle.displayName)?"
        alert.informativeText = "This removes the app's files and cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let before = filteredSort
        let removedIndex = before.firstIndex { $0.id == bottle.id }

        try? FileManager.default.removeItem(at: bottle.url)
        bottleVM.bottlesList.paths.removeAll { $0 == bottle.url }
        bottleVM.loadBottles()

        // Sidebar mode's pane follows the selection automatically; picking the
        // neighbor here means it never has to show a blank pane just because
        // the entry it was showing is gone.
        if let removedIndex {
            selection.selectAfterRemoval(indexBeforeRemoval: removedIndex, in: filteredSort)
        } else {
            selection.reconcile(with: filteredSort)
        }

        // Grid mode's overlay has no bottle left to resolve, so it would
        // otherwise disappear into a blank slide-in. Sidebar mode never routes
        // to .entryDetail, so this is a no-op there.
        if case .entryDetail = route {
            withAnimation(CrosswireTheme.Motion.navigation) { route = .library }
        }
    }
}

// swiftlint:enable type_body_length

/// Floating-card background: Liquid Glass on macOS 26, the branded surface fill
/// on older systems. Only for *transient* floating elements (overlays, popovers) —
/// persistent surfaces stay branded hex per the materials-vs-hex rule.
private struct FloatingGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 14
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(in: shape)
        } else {
            content
                .background(shape.fill(CrosswireTheme.surface))
                .overlay(shape.strokeBorder(CrosswireTheme.surfaceStroke, lineWidth: 1))
        }
    }
}

/// The way out offered while an installer runs longer than expected.
/// A visible install offers Finish Setup, for portable apps that never exit.
/// A silent install offers Show Installer, which stops the background run and
/// opens the installer's own windows, in case it is stuck on a prompt nobody
/// can see.
struct InstallerEscape {
    let hint: String
    let buttonTitle: String
    let action: () -> Void
}

/// Modal overlay shown while a new app is being provisioned. When `escape`
/// is provided (during the installer-run wait) it offers a way out, so a
/// portable GUI app, which never exits, or a silent install stuck on a hidden
/// prompt can't trap the UI.
struct ProvisioningOverlay: View {
    let message: String
    var escape: InstallerEscape?

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                Text(message)
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                    .multilineTextAlignment(.center)
                if let escape {
                    VStack(spacing: 8) {
                        Text(escape.hint)
                            .font(CrosswireTheme.Typography.entryMeta)
                            .foregroundStyle(CrosswireTheme.textSecondary)
                            .multilineTextAlignment(.center)
                        Button(escape.buttonTitle, action: escape.action)
                            .buttonStyle(CrosswireButtonStyle(kind: .secondary))
                    }
                    .padding(.top, 4)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: 320)
            .padding(28)
            .animation(CrosswireTheme.Motion.hover, value: escape == nil)
            .modifier(FloatingGlassCard())
            .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
        }
    }
}

#Preview {
    ContentView(showSetup: .constant(false))
        .environmentObject(BottleVM.shared)
}

/// Hides the toolbar's copy of the window title where the system supports it,
/// and does nothing on the versions that do not. A separate modifier because
/// an `if #available` cannot sit inline in a modifier chain.
private struct HiddenToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

/// ContentView's startup prompts (first-run crash-report consent, engine update
/// available). SwiftUI alerts instead of `NSAlert.runModal()`, which blocked the
/// main actor from `onAppearTask` (CROSSWIRE-13). A separate modifier keeps the
/// already long `body` modifier chain within the type checker's limits.
private struct StartupAlerts: ViewModifier {
    @Binding var showConsentPrompt: Bool
    @Binding var showEngineUpdateAlert: Bool
    let engineUpdateMessage: String?
    let onConsent: @MainActor (CrosswireTelemetry.CrashReportingMode) -> Void
    let onEngineUpdate: @MainActor () -> Void
    let onEngineUpdateCancel: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .alert(Text(verbatim: CrosswireTelemetry.consentTitle),
                   isPresented: $showConsentPrompt,
                   actions: { consentButtons() },
                   message: { Text(verbatim: CrosswireTelemetry.consentMessage) })
            .alert(Text("update.engine.title"),
                   isPresented: $showEngineUpdateAlert,
                   actions: { engineUpdateButtons() },
                   message: { Text(verbatim: engineUpdateMessage ?? "") })
    }

    @ViewBuilder
    private func consentButtons() -> some View {
        Button("Send Automatically") { onConsent(.always) }
        Button("Ask Each Time") { onConsent(.ask) }
        Button("Don’t Send", role: .cancel) { onConsent(.never) }
    }

    @ViewBuilder
    private func engineUpdateButtons() -> some View {
        Button("update.engine.update") { onEngineUpdate() }
        Button("button.removeAlert.cancel", role: .cancel) { onEngineUpdateCancel() }
    }
}
