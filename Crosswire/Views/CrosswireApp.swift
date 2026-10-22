//
//  CrosswireApp.swift
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

import AppKit
import SwiftUI
import Sparkle
import CrosswireKit
import OSLog

@main
struct CrosswireApp: App {
    @State var showSetup: Bool = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openURL) var openURL
    /// Dark / Light / System, set in the setup flow and Settings.
    @AppStorage(AppearancePreference.defaultsKey) private var appearanceRaw =
        AppearancePreference.fallback.rawValue
    @StateObject private var failureWatcher = FailureWatcher()
    private let updaterController: CrosswireUpdateController

    /// The stored preference, falling back when unset or unrecognized.
    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .fallback
    }

    init() {
        CrosswireTelemetry.startIfEnabled()
        // Channel-aware appcast + "reinstall stable" back-out (shared delegate; held weakly).
        updaterController = CrosswireUpdateController()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showSetup: $showSetup, sparkleUpdater: updaterController.updater)
                // Opens at the usual size and can be resized between a narrow
                // list and a wide window. The minimum keeps the list readable
                // when the detail pane steps aside.
                .frame(minWidth: WindowSize.minWidth, idealWidth: WindowSize.width, maxWidth: .infinity,
                       minHeight: WindowSize.minHeight, idealHeight: WindowSize.height, maxHeight: .infinity)
                .environmentObject(BottleVM.shared)
                // One override drives every Color(light:dark:) token in both
                // theme files, so the user's Dark / Light / System choice
                // reaches the whole UI without any view consulting it.
                .preferredColorScheme(appearance.colorScheme)
                .onChange(of: appearanceRaw, initial: true) {
                    NSApp.appearance = appearance.nsAppearance
                }
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                    updaterController.start()

                    Task.detached {
                        await CrosswireApp.deleteOldLogs()
                    }
                    Task.detached {
                        CrosswireEngine.removeLegacyEngineIfNeeded()
                    }
                }
        }
        // Native unified toolbar: inline title at the leading edge, larger
        // bold controls, and free compact-on-narrow behavior. Replaces the
        // old custom header HStack (Brief 2 / Commit 2, HIG alignment).
        .windowToolbarStyle(.unifiedCompact)
        // The content sets a minimum, and the window can grow past it.
        .windowResizability(.contentMinSize)
        // Don't ask me how this works, it just does
        .handlesExternalEvents(matching: ["{same path of URL?}"])
        .commands {
            LibraryViewCommands()
            CommandGroup(after: .appInfo) {
                SparkleView(updater: updaterController.updater)
            }
            CommandGroup(before: .systemServices) {
                Divider()
                // Directly under Settings, which is where a Mac user looks for
                // it. It used to sit below Setup and Install CLI, two items
                // most people never touch, so the one irreversible entry in
                // this menu was the hardest to find. Anchoring it after
                // .appSettings puts it ABOVE Settings, not below, so it goes
                // at the head of the next group instead.
                Button("uninstall.menu") {
                    CrosswireApp.confirmUninstall()
                }
                Divider()
                Button("open.setup") {
                    showSetup = true
                }
                Button("install.cli") {
                    Task {
                        await CrosswireCmd.install()
                    }
                }
            }
            LibraryCommands()
            CommandGroup(after: .newItem) {
                Button("open.bottle") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    panel.begin { result in
                        if result == .OK {
                            if let url = panel.urls.first {
                                BottleVM.shared.bottlesList.paths.append(url)
                                BottleVM.shared.loadBottles()
                            }
                        }
                    }
                }
                .keyboardShortcut("I", modifiers: [.command])
            }
            CommandGroup(after: .importExport) {
                Button("open.logs") {
                    CrosswireApp.openLogsFolder()
                }
                .keyboardShortcut("L", modifiers: [.command])
                Button("kill.bottles") {
                    CrosswireApp.killBottles()
                }
                .keyboardShortcut("K", modifiers: [.command, .shift])
                Button("wine.clearShaderCaches") {
                    CrosswireApp.killBottles() // Better not make things more complicated for ourselves
                    CrosswireApp.wipeShaderCaches()
                }
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Crosswire") {
                    CrosswireApp.openAboutWindow()
                }
            }
            CommandGroup(replacing: .help) {
                Button("help.website") {
                    if let url = URL(string: "https://casitasoftware.com") {
                        openURL(url)
                    }
                }
                Button("help.wiki") {
                    if let url = URL(string: "https://casitasoftware.com/crosswire/wiki/") {
                        openURL(url)
                    }
                }
                Button("help.github") {
                    if let url = URL(string: "https://github.com/casitasoftware/crosswire-source") {
                        openURL(url)
                    }
                }
                Divider()
                Button("Diagnostics...") {
                    CrosswireApp.openDiagnosticsWindow()
                }
            }
        }
        // A real Settings scene, which also restores the app-menu item and
        // Cmd+, for free. It replaces the inline destination that used to
        // slide over the library: changing a setting no longer means losing
        // sight of what you were doing.

        Settings {
            SettingsRootView(updater: updaterController.updater)
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowResizability(.contentSize)
    }

    // MARK: - Window helpers

    @MainActor static func openAboutWindow() {
        let existing = NSApp.windows.first { $0.title == "About Crosswire" }
        if let existingWindow = existing {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = NSHostingView(rootView: AboutView())
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Crosswire"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor static func openDiagnosticsWindow() {
        let existing = NSApp.windows.first { $0.title == "Diagnostics" }
        if let existingWindow = existing {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = NSHostingView(rootView: DiagnosticsView())
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Diagnostics"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor static func killBottles() {
        for bottle in BottleVM.shared.bottles {
            do {
                try Wine.killBottle(bottle: bottle)
            } catch {
                print("Failed to kill bottle: \(error)")
            }
        }
    }

    // Uninstall flow (Tier 1 confirm, Tier 2 confirm, and the actual data
    // removal) lives in CrosswireApp+Uninstall.swift (#110) to keep this
    // file under the line-length limit.

    static func openLogsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Wine.logsFolder.path)
    }

    static func deleteOldLogs() {
        let pastDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: Wine.logsFolder,
            includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let logs = urls.filter { url in
            url.pathExtension == "log"
        }

        let oldLogs = logs.filter { url in
            do {
                let resourceValues = try url.resourceValues(forKeys: [.creationDateKey])

                return resourceValues.creationDate ?? Date() < pastDate
            } catch {
                return false
            }
        }

        for log in oldLogs {
            do {
                try FileManager.default.removeItem(at: log)
            } catch {
                print("Failed to delete log: \(error)")
            }
        }
    }

    static func wipeShaderCaches() {
        let getconf = Process()
        getconf.executableURL = URL(fileURLWithPath: "/usr/bin/getconf")
        getconf.arguments = ["DARWIN_USER_CACHE_DIR"]
        let pipe = Pipe()
        getconf.standardOutput = pipe
        do {
            try getconf.run()
        } catch {
            return
        }
        getconf.waitUntilExit()
        let getconfOutput = {() -> Data in
            if #available(macOS 10.15, *) {
                do {
                    return try pipe.fileHandleForReading.readToEnd() ?? Data()
                } catch {
                    return Data()
                }
            } else {
                return pipe.fileHandleForReading.readDataToEndOfFile()
            }
        }()
        guard let getconfOutputString = String(data: getconfOutput, encoding: .utf8) else {return}
        let d3dmPath = URL(fileURLWithPath: getconfOutputString.trimmingCharacters(in: .whitespacesAndNewlines))
            .appending(path: "d3dm").path
        do {
            try FileManager.default.removeItem(atPath: d3dmPath)
        } catch {
            return
        }
    }
}

// MARK: - Library menu commands

/// What the File menu can do for the library window in front.
///
/// The library owns the selection and the install flow, so the menu asks it
/// through a focused value instead of keeping its own copy of either. With no
/// library window focused the value is nil and the items disable themselves.
struct LibraryMenuActions {
    /// Same flow as the toolbar's Install App.
    let install: () -> Void
    /// Launches the selected app. Nil when nothing is selected.
    let openSelected: (() -> Void)?
}

private struct LibraryMenuActionsKey: FocusedValueKey {
    typealias Value = LibraryMenuActions
}

extension FocusedValues {
    var libraryMenuActions: LibraryMenuActions? {
        get { self[LibraryMenuActionsKey.self] }
        set { self[LibraryMenuActionsKey.self] = newValue }
    }
}

/// File > Install App… (Command-N) and File > Open (Command-O).
///
/// Command-I stays with Import App. Command-N is free because the app has no
/// documents, and Install App is how a new entry gets made. Command-O opens the
/// selected app, which is what Return and double-click already do.
struct LibraryCommands: Commands {
    @FocusedValue(\.libraryMenuActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Install App…") { actions?.install() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
            Button("Open") { actions?.openSelected?() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(actions?.openSelected == nil)
        }
    }
}
