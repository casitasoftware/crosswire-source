//
//  ContentView+Install.swift
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
import UniformTypeIdentifiers
import CrosswireKit
import os.log

// swiftlint:disable file_length
extension ContentView {
    /// Delay before the "Finish Setup" escape hatch appears on the installer
    /// overlay — real installers usually finish faster, so we don't offer the
    /// out prematurely during a quick install (which could finalize mid-run).
    static let installerFinishHintDelay: Duration = .seconds(20)
    /// Long backstop so a walked-away portable-app install eventually finalizes
    /// rather than hanging on "Running installer…" forever.
    static let installerBackstopTimeout: Duration = .seconds(600)

    /// Wait for the installer task to exit, OR for the user to tap "Finish
    /// Setup", OR a long backstop — whichever comes first. Returns true ONLY if
    /// the installer actually exited. On an early finish the launched process is
    /// left running (it's the user's app); the caller finalizes + adopts it.
    /// This is what keeps a portable GUI app (which never exits) from trapping
    /// the UI on "Running installer…". Everything runs on the main actor, so the
    /// `done` guard needs no extra synchronization.
    ///
    /// A silent run is different. It always exits, it has no app to adopt
    /// early, and a large one can legitimately take longer than the backstop.
    /// Finalizing while it still runs would start the visible fallback beside
    /// it, so there is no backstop, and the escape is Show Installer instead
    /// of Finish Setup. Returning false then means the user abandoned the
    /// silent run.
    @MainActor
    func waitForInstallerOrFinish(_ task: Task<Error?, Never>, silent: Bool = false) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            var done = false
            func finish(installerExited: Bool) {
                guard !done else { return }
                done = true
                installerEscape = nil
                cont.resume(returning: installerExited)
            }
            // The installer exited on its own (normal installer path).
            Task { @MainActor in _ = await task.value; finish(installerExited: true) }
            // After a short delay, surface the escape hatch.
            Task { @MainActor in
                try? await Task.sleep(for: Self.installerFinishHintDelay)
                guard !done else { return }
                installerEscape = silent
                    ? InstallerEscape(hint: "Taking a while? You can open the installer instead.",
                                      buttonTitle: "Show Installer",
                                      action: { finish(installerExited: false) })
                    : InstallerEscape(hint: "If your app is already open, you can finish setup.",
                                      buttonTitle: "Finish Setup",
                                      action: { finish(installerExited: false) })
            }
            // Hard backstop so a visible run can never hang forever.
            guard !silent else { return }
            Task { @MainActor in
                try? await Task.sleep(for: Self.installerBackstopTimeout)
                finish(installerExited: false)
            }
        }
    }

    /// Await the bottle's wineserver teardown, but never longer than `timeout`.
    /// `Wine.killBottleAndWait` runs `wineserver -k -w`, which a stuck/zombie
    /// wine client (one that survives the kill) can make wait forever — and an
    /// unbounded wait would freeze the post-install flow with no escape. This
    /// races the teardown against a backstop and returns on whichever lands
    /// first; on timeout the teardown task is left to finish on its own (a
    /// harmlessly-waiting wineserver) while the caller proceeds. Same
    /// main-actor `done`-guard pattern as `waitForInstallerOrFinish` — no extra
    /// synchronization needed.
    @MainActor
    func killBottleBounded(_ bottle: Bottle, timeout: Duration = .seconds(20)) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var done = false
            func finish() {
                guard !done else { return }
                done = true
                cont.resume()
            }
            Task { @MainActor in
                try? await Wine.killBottleAndWait(bottle: bottle)
                finish()
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                finish()
            }
        }
    }

    func installWindowsApp() {
        // Concurrent-install guard. provisionAndInstall is @MainActor and
        // its `await`s suspend the main actor. Two of these in flight at
        // the same time deadlocked the UI on 2026-05-28 when bug #94's
        // wineserver-await held the first install open and the second
        // install was started. provisioningMessage is set synchronously on
        // entry and cleared on exit, so it's a reliable in-flight signal.
        if provisioningMessage != nil {
            showInstallAlert(
                title: "Install already in progress",
                body: "Wait for the current install to finish before starting a new one. "
                    + "You can see its progress in the status row at the bottom of the window."
            )
            return
        }
        // Separate from the provisioningMessage guard above: that one only
        // covers the install itself, not the picker sitting open beforehand.
        // Without this, pressing Install twice before picking a file in the
        // first panel opens two (or more) NSOpenPanels concurrently.
        if installPickerOpen {
            showInstallAlert(
                title: "Install already in progress",
                body: "A file picker is already open. Pick a file there, or cancel it, before starting another."
            )
            return
        }
        installPickerOpen = true
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType.exe,
            UTType(exportedAs: "com.microsoft.msi-installer"),
            UTType(exportedAs: "com.microsoft.bat"),
            UTType(filenameExtension: "iso") ?? .diskImage
        ]
        panel.begin { result in
            installPickerOpen = false
            guard result == .OK, let pickedURL = panel.urls.first else { return }
            // #120: log the exact URL NSOpenPanel handed back, before any
            // Crosswire naming/routing logic touches it, so a future
            // wrong-name repro shows whether it was already wrong here.
            Logger.wineKit.error(
                "[install-entry] NSOpenPanel picked: \(pickedURL.path(percentEncoded: false), privacy: .public)"
            )
            // Defense in depth: re-check at the actual Task entry in case
            // the user re-opened the panel via a different code path while
            // the previous panel was open.
            Task { @MainActor in
                if provisioningMessage != nil {
                    showInstallAlert(
                        title: "Install already in progress",
                        body: "Wait for the current install to finish."
                    )
                    return
                }
                await installRouting(pickedURL)
            }
        }
    }

    /// Handle files dropped onto the library — treat the first dropped Windows
    /// installer/executable (.exe / .msi / .bat) or disc image (.iso) exactly
    /// like one picked via the "Install" button. Anything else is ignored.
    @MainActor
    func handleDrop(of urls: [URL]) -> Bool {
        let installable = urls.first {
            ["exe", "msi", "bat", "iso"].contains($0.pathExtension.lowercased())
        }
        guard let pickedURL = installable else {
            // Say so. A drop that does nothing looks like a broken drop target.
            showInstallAlert(
                title: "That file can't be installed",
                body: "Crosswire installs Windows programs from .exe, .msi and .bat installers, "
                    + "and from .iso disc images."
            )
            return false
        }
        // #120: same rationale as the NSOpenPanel log above, for the drop path.
        Logger.wineKit.error(
            "[install-entry] drop picked: \(pickedURL.path(percentEncoded: false), privacy: .public)"
        )
        if provisioningMessage != nil {
            showInstallAlert(
                title: "Install already in progress",
                body: "Wait for the current install to finish before starting a new one."
            )
            return false
        }
        Task { @MainActor in await installRouting(pickedURL) }
        return true
    }

    /// Route a picked file to the right install path: disc images are mounted
    /// and their installer located first; everything else installs directly.
    @MainActor
    func installRouting(_ pickedURL: URL) async {
        guard pickedURL.pathExtension.lowercased() == "iso" else {
            await provisionAndInstall(pickedURL: pickedURL)
            return
        }
        provisioningMessage = "Opening disc image…"
        let volume: URL
        do {
            volume = try DiscImage.mount(pickedURL)
        } catch {
            provisioningMessage = nil
            showInstallAlert(
                title: "Couldn't open the disc image",
                body: error.localizedDescription
            )
            return
        }
        defer { DiscImage.unmount(volume) }
        guard let installer = DiscImage.findInstaller(in: volume) else {
            provisioningMessage = nil
            showInstallAlert(
                title: "No installer found on the disc",
                body: "Crosswire looked for an installer on \(volume.lastPathComponent) "
                    + "but couldn't find one. Open the disc image in Finder and pick "
                    + "the installer .exe directly via Install."
            )
            return
        }
        await provisionAndInstall(pickedURL: installer)
    }

    // swiftlint:disable function_body_length
    @MainActor
    func provisionAndInstall(pickedURL: URL) async {
        // Decided before a bottle exists, so Cancel leaves nothing behind.
        guard let mode = await chooseInstallMode(for: pickedURL) else {
            provisioningMessage = nil
            return
        }
        let bottleName = pickedURL.deletingPathExtension().lastPathComponent
        let defaultLocation = UserDefaults.standard.url(forKey: "defaultBottleLocation")
            ?? BottleData.defaultBottleDir

        provisioningMessage = "Setting up..."
        let newBottleURL = bottleVM.createNewBottle(
            bottleName: bottleName,
            winVersion: .win10,
            bottleURL: defaultLocation
        )

        let bottle = await waitForBottle(url: newBottleURL)
        guard let bottle else {
            provisioningMessage = nil
            showInstallAlert(
                title: "Could not set up \(bottleName)",
                body: "Crosswire was unable to prepare a new environment for this app. "
                    + "See the latest run log for details: ~/Library/Logs/app.Crosswire.Crosswire/."
            )
            return
        }

        // Apply a matching recipe (known-good prerequisites + overrides for this
        // specific title) before anything else — see CrosswireKit/Recipe.swift.
        // Generic PE-import runtime detection below still runs as a complement.
        await applyRecipeIfMatched(pickedURL, into: bottle)

        // Static-analyze the picked exe's PE imports BEFORE running it. If we
        // detect runtimes the bottle doesn't have (vcrun, dotnet, d3dx, etc.),
        // surface a confirmation sheet that installs them via winetricks
        // first. .msi / .bat get skipped because their PE imports don't
        // describe what the installer will run.
        let detected = pickedURL.pathExtension.lowercased() == "exe"
            ? RuntimeDetector.detect(at: pickedURL)
            : []
        if !detected.isEmpty {
            provisioningMessage = nil
            let installed = await presentRuntimesSheet(
                exeName: pickedURL.lastPathComponent, detected: detected, bottle: bottle
            )
            provisioningMessage = mode.silentArguments != nil
                ? "Installing \(mode.appName)…"
                : "Running \(installed.isEmpty ? "installer" : "installer (runtimes ready)")..."
        } else {
            provisioningMessage = mode.silentArguments != nil ? "Installing \(mode.appName)…" : "Running installer..."
        }
        // runInstaller uses direct `wine <path>` invocation (not `start /unix`)
        // so it returns as soon as the installer's own .exe exits, NOT when
        // wineserver releases (Bug #94). But a *portable* GUI app (e.g. putty.exe)
        // run this way never exits on its own, which would trap us on "Running
        // installer…" forever. So wait for the installer to exit OR for the user
        // to tap "Finish Setup" OR a long backstop — whichever first. On an early
        // finish we leave the process running (it's the user's app) and fall
        // through to finalize + adopt it.
        var installerError = await runInstallerOnce(pickedURL, in: bottle, arguments: mode.silentArguments)
        if installerError is CancellationError {
            provisioningMessage = nil
            return
        }
        bottle.finalizeAppIdentity()

        // A silent run that failed, or finished without leaving anything to
        // launch, gets one more try with the installer's own windows, in the
        // same bottle. Covers installers that reject silent mode, and ones
        // whose silent defaults skip what the user actually wanted.
        if mode.silentArguments != nil,
           installerError is SilentInstallFailed || bottle.userVisiblePrograms.isEmpty {
            provisioningMessage = "Opening the installer…"
            installerError = await runInstallerOnce(pickedURL, in: bottle, arguments: nil)
            bottle.finalizeAppIdentity()
        }

        if installerError is CancellationError {
            provisioningMessage = nil
            return
        }
        if let installerError {
            provisioningMessage = nil
            presentInstallerFailure(installerError)
            return
        }

        // If the install scan found nothing AND the picked file was a
        // portable .exe (no .msi, no .bat), treat the .exe itself as the
        // app — copy it into the bottle so Crosswire's program scan picks
        // it up and the Run button works. Without this, self-contained
        // tools like the SWG Legends launcher (10MB Java launcher with
        // bundled JRE) trigger a "no apps detected" warning even though
        // the .exe IS the app the user wanted to run.
        //
        // Never for an installer, though: one that installed nothing is a
        // failed install, not a portable app. StarCraft's SETUP.EXE, run off
        // its disc, was copied in and listed in the library as "SETUP".
        let pickedIsInstaller = await Task.detached(priority: .userInitiated) {
            (try? PEFile(url: pickedURL))?.installerKind != nil
        }.value
        if bottle.userVisiblePrograms.isEmpty,
           pickedURL.pathExtension.lowercased() == "exe",
           !pickedIsInstaller,
           await adoptPortableExe(pickedURL, into: bottle) {
            provisioningMessage = nil
            return
        }

        // After a regular installer run, scan the detected programs for
        // self-contained Java launchers (e.g. JavaFX game launchers that
        // ship their own JRE next to the .exe). For each match with no
        // existing per-program plist, seed one with _JAVA_OPTIONS so the
        // first launch doesn't sliver-render under Prism d3d. Runs
        // before any auto-launch attempt. Orthogonal to RuntimeDetector,
        // which only sees Win32 PE imports.
        for program in bottle.userVisiblePrograms {
            await JavaAppDetector.applyDefaultsIfNeeded(forExeAt: program.url, in: bottle)
        }

        // Clean up anything the installer may have already spawned (notably
        // the "Run <app> after install" Finish-step launcher in Inno Setup
        // and friends). That launcher started BEFORE the auto-features
        // above were applied, so its JVM read empty env vars and the
        // dwrite override wasn't yet in user.reg — net result is a sliver-
        // render or post-Login crash on what looks to the user like the
        // first run of their freshly-installed app. Killing the bottle's
        // wineserver takes the half-configured launcher down so the auto-
        // launch below starts cleanly with all auto-features applied. Waiting
        // for teardown (vs the old fire-and-forget kill + 2s sleep) is what
        // stops the relaunch racing a half-dead wineserver — the cause of the
        // post-install "blank launcher window". The wait is BOUNDED: a stuck or
        // zombie wine client can make `wineserver -w` block forever, and an
        // unbounded wait here would freeze the install flow with no escape, so
        // we cap it and proceed (the relaunch starts a fresh wineserver anyway).
        //
        // Snapshot the bottle's running PIDs before killing them. These are
        // passed to runPrimary so the single-instance guard in run() can
        // exclude them: after wineserver -k the killed PIDs remain visible in
        // ps -E during the kernel reaping window, and NSRunningApplication
        // still returns non-nil with .isTerminated == false (KVO lag). Captured
        // before the kill to ensure we get the full set even if the kill is fast.
        let killedPIDs = Set(Wine.runningProcessIDs(for: bottle))
        await killBottleBounded(bottle)

        provisioningMessage = nil

        if bottle.userVisiblePrograms.isEmpty {
            offerToRemoveEmptyEntry(bottle, installerURL: pickedURL)
            return
        }

        // Auto-launch the freshly-installed app. The installer's wizard
        // promised "Run <app> after install" — we just killed THAT launcher
        // because it started before our auto-features applied. Auto-launch
        // here gives the user what they expected (their app opens), now with
        // the plist's _JAVA_OPTIONS + dwrite=builtin in effect from first
        // paint. The killBottleAndWait above already blocked until the old
        // wineserver exited, so this relaunch comes up against a clean prefix
        // (no sleep-race).
        runPrimary(for: bottle, excludingPIDs: killedPIDs)
    }
    // swiftlint:enable function_body_length

    /// Apply a matching recipe's DLL overrides + winetricks prerequisites to a
    /// fresh bottle (reusing the existing runners), before the user's installer
    /// runs. No-op when no recipe matches the picked installer.
    @MainActor
    private func applyRecipeIfMatched(_ pickedURL: URL, into bottle: Bottle) async {
        guard let recipe = RecipeMatcher.match(installerURL: pickedURL) else { return }
        provisioningMessage = "Applying \(recipe.name) setup…"
        for (dll, value) in recipe.dllOverrides {
            try? await Wine.setDllOverrideIfAbsent(dll, value: value, bottle: bottle)
        }
        if recipe.useDXVK {
            // Persisted via BottleSettings' didSet. enableDXVK no-ops at launch
            // if the installed engine doesn't ship DXVK, so this is safe even
            // on the non-DXVK prod engine.
            bottle.settings.dxvk = true
        }
        if !recipe.prerequisites.isEmpty {
            _ = await Winetricks.runVerbs(recipe.prerequisites, bottle: bottle)
        }
    }

    /// Present the runtimes-detected sheet and suspend until the user
    /// makes a decision. Returns the verbs that were actually installed
    /// (empty when the user skipped).
    @MainActor
    func presentRuntimesSheet(
        exeName: String, detected: [DetectedRuntime], bottle: Bottle
    ) async -> [String] {
        await withCheckedContinuation { continuation in
            runtimesPrompt = RuntimesPrompt(
                exeName: exeName,
                detected: detected,
                bottle: bottle,
                continuation: continuation
            )
        }
    }

    /// Copy a portable .exe the user picked into the bottle's
    /// `Program Files (x86)/<stem>/` so subsequent program scans and the
    /// Run button can find it. Sets primaryProgramURL + userVisible to
    /// the in-bottle path. Returns true on success.
    private func adoptPortableExe(_ source: URL, into bottle: Bottle) async -> Bool {
        let stem = source.deletingPathExtension().lastPathComponent
        let targetDir = bottle.url
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: stem)
        let targetURL = targetDir.appending(path: source.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) {
                try FileManager.default.copyItem(at: source, to: targetURL)
            }
        } catch {
            print("Failed to adopt portable exe \(source.lastPathComponent): \(error)")
            return false
        }
        bottle.updateInstalledPrograms()
        bottle.settings.primaryProgramURL = targetURL
        bottle.settings.userVisibleProgramURLs = [targetURL]

        // Check the SOURCE dir tree for a bundled JRE — that's where the
        // lib/jre layout lives; we only copy the .exe into the bottle,
        // not the surrounding tree. The plist is written for the
        // in-bottle target path (same basename as source, so the helper
        // keys it correctly off lastPathComponent).
        await JavaAppDetector.applyDefaultsIfNeeded(forExeAt: source, in: bottle)
        return true
    }

    /// Offers a background install when the installer's engine has a known
    /// silent mode (NSIS, Inno Setup). Returns nil if the user cancels.
    ///
    /// Installing silently accepts the installer's license on the user's
    /// behalf, so it is offered, never assumed, and Show Installer is always
    /// available for reading the license or choosing install options.
    @MainActor
    private func chooseInstallMode(for url: URL) async -> InstallMode? {
        let (kind, strings) = await Task.detached(priority: .userInitiated) {
            () -> (InstallerKind?, [String: String]) in
            guard url.pathExtension.lowercased() == "exe", let peFile = try? PEFile(url: url) else {
                return (nil, [:])
            }
            return (peFile.installerKind, peFile.versionStrings())
        }.value
        // ProductName first; LOTRO's installer has none but describes itself
        // as "The Lord of the Rings Online".
        let appName = strings["ProductName"].flatMap(DisplayName.fromProductName)
            ?? strings["FileDescription"].flatMap(DisplayName.fromProductName)
            ?? DisplayName.fromInstallerFilename(url.deletingPathExtension().lastPathComponent)
            ?? url.deletingPathExtension().lastPathComponent

        guard let silentArguments = kind?.silentArguments else {
            return InstallMode(silentArguments: nil, appName: appName)
        }
        let alert = NSAlert()
        alert.messageText = "Install \(appName)?"
        alert.informativeText = "Crosswire can install it in the background, without the installer's windows. "
            + "This accepts \(appName)'s license agreement on your behalf.\n\n"
            + "Choose Show Installer to read the license or pick install options yourself."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Show Installer")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return InstallMode(silentArguments: silentArguments, appName: appName)
        case .alertSecondButtonReturn:
            return InstallMode(silentArguments: nil, appName: appName)
        default:
            return nil
        }
    }

    /// Runs the installer once and waits for it. With `arguments` (a silent
    /// run) there is no window to bring forward, and a non-zero exit or the
    /// user choosing Show Installer comes back as `SilentInstallFailed`, so
    /// the caller can fall back to a visible run.
    @MainActor
    private func runInstallerOnce(_ url: URL, in bottle: Bottle, arguments: [String]?) async -> Error? {
        let silent = arguments != nil
        if !silent {
            Self.activateFreshLaunch(for: bottle, excludingPIDs: Set(Wine.runningProcessIDs(for: bottle)))
        }
        let run = Task<Error?, Never> {
            do {
                let report = try await Wine.runInstaller(at: url, bottle: bottle, arguments: arguments ?? [])
                if report.completion == .cancelled || report.completion == .requestedStop {
                    return CancellationError()
                }
                if report.isAbnormal {
                    if silent { return SilentInstallFailed(exitCode: report.exitCode) }
                    var details: [String: Any] = ["observedFailure": true]
                    if let url = report.logFileURL { details["runLogURL"] = url }
                    return NSError(domain: "Crosswire.Install", code: Int(report.exitCode), userInfo: details)
                }
                return nil
            } catch {
                return error
            }
        }
        guard await waitForInstallerOrFinish(run, silent: silent) else {
            guard silent else { return nil }   // Finish Setup: adopt what is running
            // Show Installer: stop the background run before the visible one
            // starts, so two copies of the installer never run at once.
            await killBottleBounded(bottle)
            return SilentInstallFailed(exitCode: nil)
        }
        let error = await run.value
        if let error { print("Failed to run installer: \(error)") }
        return error
    }

    /// The install produced nothing to launch. Say so plainly and offer to
    /// take the empty entry out of the library, instead of leaving it there
    /// looking like an app. Keep is the default button: an installer can
    /// write files somewhere Crosswire does not detect, and pressing Return
    /// must not delete them.
    private func offerToRemoveEmptyEntry(_ bottle: Bottle, installerURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Nothing was installed"
        var body = "\(installerURL.lastPathComponent) finished, but Crosswire could not find an app to launch."
        if installerURL.path(percentEncoded: false).hasPrefix("/Volumes/") {
            body += " Installers that run from a disc often expect the disc to appear as a drive, "
                + "which Crosswire does not do yet."
        }
        body += "\n\nRemoving it deletes anything the installer wrote. "
            + "The run log is in ~/Library/Logs/app.Crosswire.Crosswire/."
        alert.informativeText = body
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep")
        let remove = alert.addButton(withTitle: "Remove from Library")
        remove.hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            bottle.remove(delete: true)
        }
    }

    private func presentInstallerFailure(_ error: Error) {
        let details = (error as NSError).userInfo
        let alreadyObserved = details["observedFailure"] as? Bool == true
        if !alreadyObserved { CrosswireTelemetry.capture(error, context: "install.runInstaller") }
        // Always offer recovery: a prior failed silent attempt can debounce
        // the separate consent prompt for this visible retry.
        let alert = NSAlert()
        alert.messageText = "Installation didn't finish"
        alert.informativeText = "The installer stopped before Crosswire could finish. Save the log before trying again."
        alert.addButton(withTitle: "Show Log")
        alert.addButton(withTitle: "Dismiss")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = details["runLogURL"] as? URL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(Wine.logsFolder)
            }
        }
    }

    private func showInstallAlert(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    func waitForBottle(url: URL) async -> Bottle? {
        // createNewBottle spawns an inner Task; poll the published list until
        // the bottle flips out of inFlight. ~30s ceiling.
        for _ in 0..<300 {
            if let bottle = bottleVM.bottles.first(where: { $0.url == url }), !bottle.inFlight {
                return bottle
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return bottleVM.bottles.first(where: { $0.url == url })
    }

    func runPrimary(for bottle: Bottle, excludingPIDs: Set<pid_t> = []) {
        guard bottle.isAvailable else { return }
        bottle.finalizeAppIdentity()
        guard !bottle.programs.isEmpty else {
            showInstallAlert(title: "Couldn't find an app to open",
                             body: "Choose the app's program file, or run its installer again.")
            return
        }
        if let program = primaryProgram(for: bottle) {
            run(program: program, bottle: bottle, excludingPIDs: excludingPIDs)
        } else {
            chooseLaunchProgram(for: bottle, excludingPIDs: excludingPIDs)
        }
    }

    /// Resolve an ambiguous launch where the user clicked Play, rather than
    /// navigating to the same detail page with no explanation.
    private func chooseLaunchProgram(for bottle: Bottle, excludingPIDs: Set<pid_t>) {
        let programs = bottle.programs
        let alert = NSAlert()
        alert.messageText = "Choose a program to open"
        alert.informativeText = "Crosswire found more than one program. Your choice will be used next time."
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
        picker.addItems(withTitles: programs.map {
            $0.url.path.replacingOccurrences(of: bottle.url.appending(path: "drive_c").path + "/", with: "")
        })
        alert.accessoryView = picker
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
              programs.indices.contains(picker.indexOfSelectedItem) else { return }
        let program = programs[picker.indexOfSelectedItem]
        bottle.settings.primaryProgramURL = program.url
        var visible = bottle.settings.userVisibleProgramURLs ?? []
        if !visible.contains(where: { $0.isSameWindowsPath(as: program.url) }) {
            visible.append(program.url)
        }
        bottle.settings.userVisibleProgramURLs = visible
        run(program: program, bottle: bottle, excludingPIDs: excludingPIDs)
    }

    /// The program a Launch should run: an explicit primary if set and still
    /// present, else the first user-visible program, else the sole installed
    /// program. `nil` means we can't pick one unambiguously (caller presents
    /// a program picker). Assumes `programs` is already
    /// populated and non-empty.
    func primaryProgram(for bottle: Bottle) -> Program? {
        let programs = bottle.programs
        if let primaryURL = bottle.settings.primaryProgramURL,
           let primary = programs.first(where: { $0.url.isSameWindowsPath(as: primaryURL) }) {
            return primary
        }
        if let firstVisible = bottle.userVisiblePrograms.first {
            return firstVisible
        }
        return programs.count == 1 ? programs.first : nil
    }

    /// Launch the primary program with full-lifetime output capture (direct
    /// `wine` invocation, not detached). Used to reproduce crashes: the app
    /// runs as a foreground child and its complete stdout/stderr stream to the
    /// per-run log; on exit we reveal that log plus any JVM crash dump the run
    /// produced. See `Wine.runProgram(captureDiagnostics:)`.
    @MainActor
    func runWithDiagnostics(for bottle: Bottle) {
        guard bottle.isAvailable else { return }
        bottle.updateInstalledPrograms()
        guard !bottle.programs.isEmpty, let program = primaryProgram(for: bottle) else {
            withAnimation(CrosswireTheme.Motion.navigation) { route = .entryDetail(bottle.id) }
            return
        }
        bottle.settings.lastLaunched = Date()
        let startedAt = Date()
        let exeName = program.url.lastPathComponent
        Task(priority: .userInitiated) {
            let report = try? await Wine.runProgram(
                at: program.url, bottle: bottle, captureDiagnostics: true
            )
            // The foreground wine returns early if the app re-execs a detached
            // child (e.g. a JVM launcher forking `javaw`). Wait until the
            // launched exe is gone from the process list before collecting
            // artifacts, so a crash that happens minutes after the foreground
            // process exited still gets caught (its hs_err lands on disk).
            await Self.waitForExit(ofExe: exeName)
            await MainActor.run {
                presentDiagnostics(report: report, bottle: bottle, since: startedAt)
            }
        }
    }

    /// Poll until no process mentions `exeName` in its argv, capped so a
    /// long-running app can't hang the diagnostics flow forever. A short
    /// initial delay lets a detached child appear before the first check.
    private static func waitForExit(ofExe exeName: String) async {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let deadline = Date().addingTimeInterval(10 * 60)
        while Date() < deadline {
            if !Wine.isProcessRunning(matching: exeName) { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    /// After a diagnostics launch exits, surface what was captured: the run log
    /// and any `hs_err_pid*.log` (JVM crash dump) written during the run.
    @MainActor
    private func presentDiagnostics(report: ProgramRunReport?, bottle: Bottle, since: Date) {
        let crashDump = recentCrashDump(in: bottle, since: since)
        let alert = NSAlert()
        alert.messageText = "Diagnostics captured"
        // Lead with whether a crash dump was found — that's the real evidence.
        // The run report's exit code reflects only the foreground process,
        // which is unreliable for apps that re-exec a detached child, so it's
        // not surfaced here.
        var info: String
        if crashDump != nil {
            info = "\(bottle.displayName) wrote a crash dump during this run — "
                + "that's the most useful evidence for a Report."
        } else {
            info = "\(bottle.displayName) exited without writing a crash dump."
        }
        if report?.logFileURL != nil {
            info += "\nThe run log captured the launch environment and any "
                + "early output."
        }
        alert.informativeText = info
        if report?.logFileURL != nil {
            alert.addButton(withTitle: "Reveal Log")
        }
        if crashDump != nil {
            alert.addButton(withTitle: "Reveal Crash Dump")
        }
        alert.addButton(withTitle: "Close")

        let response = alert.runModal()
        var revealed: [URL] = []
        var buttonIndex = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if let log = report?.logFileURL {
            if response.rawValue == buttonIndex { revealed = [log] }
            buttonIndex += 1
        }
        if let dump = crashDump, response.rawValue == buttonIndex {
            revealed = [dump]
        }
        if !revealed.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(revealed)
        }
    }

    /// Find an `hs_err_pid*.log` under the bottle's `drive_c` modified after
    /// `since` — the JVM's own crash dump, which is the real evidence for
    /// JavaFX/JVM crashes like #84/#93.
    private func recentCrashDump(in bottle: Bottle, since: Date) -> URL? {
        let driveC = bottle.url.appending(path: "drive_c")
        guard let enumerator = FileManager.default.enumerator(
            at: driveC,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            guard name.hasPrefix("hs_err_pid"), name.hasSuffix(".log") else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if modified >= since { return url }
        }
        return nil
    }

    /// Wall-clock of the most recent launch dispatched per bottle. Debounces a
    /// rapid second Launch that arrives before the first process has registered
    /// a focusable window — the single-instance guard below is blind during that
    /// startup window and would otherwise spawn a duplicate (#108).
    private static var recentLaunches: [URL: Date] = [:]

    /// Bring a freshly launched Wine process's window to the front. Wine is
    /// spawned via a bare `Process()`, which macOS never treats as a user-
    /// initiated app switch — unlike opening a real .app bundle, nothing
    /// automatically activates it. Without this, a fresh installer or
    /// program window renders behind whatever already has focus with no
    /// visual cue, and the user has to go find it in the Dock. Polls
    /// (mirrors the single-instance guard's own `runningProcessIDs` +
    /// `NSRunningApplication` pattern) rather than activating immediately,
    /// since the window doesn't exist yet the instant the process launches.
    /// `excludingPIDs` is the bottle's PID snapshot from just before this
    /// launch, so an unrelated already-running process in the same bottle
    /// is never mistaken for the one just started.
    ///
    /// 60s deadline, not a shorter one: verified live that a JVM-based
    /// launcher (SWG Legends, `javaw.exe`) registers as a regular
    /// `NSRunningApplication` well past 10s — JVM+AWT boot is genuinely
    /// slow, and this app ships Java launcher detection (JavaAppDetector)
    /// specifically because titles like this are a real, common case, not
    /// an edge case to special-case away.
    static func activateFreshLaunch(for bottle: Bottle, excludingPIDs: Set<pid_t>) {
        Task(priority: .userInitiated) {
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline {
                let fresh = Wine.runningProcessIDs(for: bottle)
                    .filter { !excludingPIDs.contains($0) }
                    .compactMap { NSRunningApplication(processIdentifier: $0) }
                    .filter { !$0.isTerminated && $0.activationPolicy == .regular }
                if let app = fresh.first {
                    app.activate(options: [.activateAllWindows])
                    return
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    func run(program: Program, bottle: Bottle, excludingPIDs: Set<pid_t> = []) {
        bottle.settings.lastLaunched = Date()
        // Re-entrancy debounce: a second Launch of the same bottle within a few
        // seconds (double-click on the Launch pill, or Launch then Return) lands
        // in the gap before the launched process shows a window, so the live-app
        // check below finds nothing and falls through to a duplicate spawn. Drop
        // the second launch. Bottles that opt into multiple instances skip this.
        if !bottle.settings.allowMultipleInstances {
            let now = Date()
            if let last = Self.recentLaunches[bottle.url], now.timeIntervalSince(last) < 3 {
                return
            }
            Self.recentLaunches[bottle.url] = now
        }
        // Single-instance: unless this bottle opts into multiple instances, a
        // Launch on an app that's already running focuses the existing window
        // instead of spawning a duplicate. We only suppress the spawn when we
        // find a live, focusable window — otherwise we fall through and launch,
        // so the guard can never get stuck blocking legitimate launches.
        //
        // excludingPIDs: PIDs the caller knows are already dead but may still
        // appear in ps -E during the kernel reaping window. Supplied by
        // provisionAndInstall (captured before killBottleBounded); empty for
        // all normal launch paths so the guard is unaffected there.
        if !bottle.settings.allowMultipleInstances {
            let liveApps = Wine.runningProcessIDs(for: bottle)
                .filter { !excludingPIDs.contains($0) }
                .compactMap { NSRunningApplication(processIdentifier: $0) }
                .filter { !$0.isTerminated }
            if let existing = liveApps.first(where: { $0.activationPolicy == .regular }) {
                existing.activate(options: [.activateAllWindows])
                return
            }
        }
        let baselinePIDs = Set(Wine.runningProcessIDs(for: bottle)).union(excludingPIDs)
        Self.activateFreshLaunch(for: bottle, excludingPIDs: baselinePIDs)
        Task(priority: .userInitiated) {
            do {
                try await Wine.runProgram(at: program.url, bottle: bottle)
            } catch {
                CrosswireTelemetry.capture(error, context: "launch.runProgram")
                showInstallAlert(title: "Couldn't open \(bottle.displayName)",
                                 body: "Try again, or use Launch with Diagnostics to save a log.")
            }
        }
    }
}

/// How one install should run, decided before its bottle is created.
struct InstallMode {
    /// Flags for a background install, or nil to show the installer's windows.
    let silentArguments: [String]?
    /// What to call the app in progress messages.
    let appName: String
}

/// A background install that did not succeed: the installer exited non-zero,
/// or `exitCode` is nil because the user chose Show Installer.
struct SilentInstallFailed: Error {
    let exitCode: Int32?
}
