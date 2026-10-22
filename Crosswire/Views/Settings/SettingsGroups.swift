//
//  SettingsGroups.swift
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
import Sparkle
import CrosswireKit
import AppKit

// MARK: - Group views

/// General settings: quit-on-terminate behavior and the app-data location
/// (a labeled section — no sub-card; "Show in Finder" reveals the path).
struct SettingsGeneralGroup: View {
    @AppStorage("killOnTerminate") var killOnTerminate = true
    @AppStorage("defaultBottleLocation") var defaultBottleLocation = BottleData.defaultBottleDir

    @AppStorage(AppearancePreference.defaultsKey) private var appearance = AppearancePreference.fallback.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Quit running apps when Crosswire quits", isOn: $killOnTerminate)
            }
            Section("App Data") {
                LabeledContent("Location", value: defaultBottleLocation.path(percentEncoded: false))
                    .textSelection(.enabled)
                HStack {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([defaultBottleLocation])
                    }
                    Button("Change…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.canCreateDirectories = true
                        panel.directoryURL = defaultBottleLocation
                        panel.begin { result in
                            if result == .OK, let url = panel.url { defaultBottleLocation = url }
                        }
                    }
                }
            }
            Section {
                trashNote
            }
        }
        .formStyle(.grouped)
    }

    /// Why dragging Crosswire to the Trash is not the whole job.
    ///
    /// Crosswire keeps installed apps and the software that runs them outside
    /// its own bundle, so deleting the bundle leaves gigabytes behind with no
    /// obvious owner. People discover that months later while hunting for disk
    /// space, which is the worst possible moment to learn it. Saying it here,
    /// next to the data location, is cheaper than a support thread.
    private var trashNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("settings.general.removing")
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Text("settings.general.removing.detail")
                .font(CrosswireTheme.Typography.entryMeta)
                .foregroundStyle(CrosswireTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("uninstall.menu") { CrosswireApp.confirmUninstall() }
                .buttonStyle(CrosswireButtonStyle(kind: .secondary))
                .padding(.top, 2)
        }
    }
}

/// About panel: app icon, name, version, and external links. The engine
/// version is intentionally NOT shown — the app surfaces no user-facing
/// engine/version strings (project naming rule).
struct SettingsAboutGroup: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Crosswire")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CrosswireTheme.textPrimary)
                    Text(appVersionString)
                        .font(CrosswireTheme.Typography.body)
                        .foregroundStyle(CrosswireTheme.textSecondary)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                aboutLink("Source Code", "https://github.com/casitasoftware/crosswire-source")
                aboutLink("Crosswire Website", "https://casitasoftware.com")
                aboutLink("Report an Issue", "https://github.com/casitasoftware/crosswire-source/issues")
            }
        }
    }

    @ViewBuilder
    private func aboutLink(_ title: String, _ urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) { openURL(url) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
                Text(title)
            }
        }
        .buttonStyle(CrosswireButtonStyle(kind: .plain, tint: CrosswireTheme.accent))
        .accessibilityLabel(title)
    }

    private var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "Version \(short)" : "Version \(short) (\(build))"
    }
}

/// Privacy: the three-state crash/incident-reporting control. Governs whether
/// Crosswire reports app crashes and abnormal game/engine exits — send
/// automatically, ask each time, or never (see `CrosswireTelemetry`). Honest copy
/// about what is and isn't collected.
struct SettingsPrivacyGroup: View {
    @AppStorage(CrosswireTelemetry.modeDefaultsKey)
    private var modeRaw = CrosswireTelemetry.mode.rawValue

    private var modeBinding: Binding<CrosswireTelemetry.CrashReportingMode> {
        Binding(
            get: { CrosswireTelemetry.CrashReportingMode(rawValue: modeRaw) ?? .ask },
            set: { CrosswireTelemetry.mode = $0 }
        )
    }

    var body: some View {
        Form {
            Picker("Crash & incident reports", selection: modeBinding) {
                ForEach(CrosswireTelemetry.CrashReportingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .tint(CrosswireTheme.accent)
            .font(CrosswireTheme.Typography.body)
            .foregroundStyle(CrosswireTheme.textPrimary)
            .disabled(!CrosswireTelemetry.isConfigured)
            Text(bodyText)
                .font(.callout)
                .foregroundStyle(CrosswireTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
    }

    private var bodyText: String {
        "Reports include diagnostic logs and app settings. Usernames and file paths are removed."
    }

}

/// Advanced: power-user maintenance actions (the same ones the menu bar exposes,
/// surfaced here for discoverability), plus the uninstall entry point (#110) --
/// a user looking for "how do I fully remove this" should find it here, not
/// only in the app menu.
struct SettingsAdvancedGroup: View {
    var body: some View {
        Form {
            row("settings.advanced.diagnostics", "settings.advanced.diagnostics.detail",
                "settings.advanced.diagnostics.button") { CrosswireApp.openDiagnosticsWindow() }
            row("settings.advanced.logs", "settings.advanced.logs.detail",
                "button.showInFinder") { CrosswireApp.openLogsFolder() }
            row("settings.advanced.runningApps", "settings.advanced.runningApps.detail",
                "settings.advanced.runningApps.button") { CrosswireApp.killBottles() }
            row("settings.advanced.graphicsCaches", "settings.advanced.graphicsCaches.detail",
                "settings.advanced.graphicsCaches.button") {
                CrosswireApp.killBottles()
                CrosswireApp.wipeShaderCaches()
            }
            Section {
                Button("uninstall.menu", role: .destructive) { CrosswireApp.confirmUninstall() }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ title: LocalizedStringKey, _ detail: LocalizedStringKey,
                     _ button: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        LabeledContent {
            Button(button, action: action)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
