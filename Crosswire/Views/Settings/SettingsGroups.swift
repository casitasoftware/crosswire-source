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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance")
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                AppearancePicker(swatchWidth: 84, swatchHeight: 54)
            }
            Divider().opacity(0.4)
            Toggle("Quit running apps when Crosswire quits", isOn: $killOnTerminate)
                .tint(CrosswireTheme.accent)
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            VStack(alignment: .leading, spacing: 8) {
                Text("App Data Location")
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                Text("Where your installed apps and their files are kept.")
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                HStack(spacing: 8) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([defaultBottleLocation])
                    }
                    .buttonStyle(CrosswireButtonStyle(kind: .secondary))
                    Button("Change…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.canCreateDirectories = true
                        panel.directoryURL = BottleData.defaultBottleDir
                        panel.begin { result in
                            if result == .OK, let url = panel.urls.first {
                                defaultBottleLocation = url
                            }
                        }
                    }
                    .buttonStyle(CrosswireButtonStyle(kind: .secondary))
                }
                .padding(.top, 2)
            }
            Divider().opacity(0.4)
            trashNote
        }
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
        VStack(alignment: .leading, spacing: 12) {
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
                .font(CrosswireTheme.Typography.entryMeta)
                .foregroundStyle(CrosswireTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bodyText: String {
        let base = "When the app or one of your games crashes, Crosswire can send a report. "
            + "It includes the run log, version information, and that app's settings, with "
            + "your username and file paths removed. It never includes your files, your "
            + "installed apps, or your account. "
            + "“Ask each time” prompts per incident so you can review what's sent first."
        return CrosswireTelemetry.isConfigured
            ? base
            : base + "\n\nReporting isn’t configured in this build."
    }
}

/// Advanced: power-user maintenance actions (the same ones the menu bar exposes,
/// surfaced here for discoverability), plus the uninstall entry point (#110) --
/// a user looking for "how do I fully remove this" should find it here, not
/// only in the app menu.
struct SettingsAdvancedGroup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("settings.advanced.diagnostics",
                "settings.advanced.diagnostics.detail",
                "settings.advanced.diagnostics.button",
                first: true) { CrosswireApp.openDiagnosticsWindow() }
            row("settings.advanced.logs",
                "settings.advanced.logs.detail",
                "button.showInFinder") { CrosswireApp.openLogsFolder() }
            row("settings.advanced.runningApps",
                "settings.advanced.runningApps.detail",
                "settings.advanced.runningApps.button") { CrosswireApp.killBottles() }
            row("settings.advanced.graphicsCaches",
                "settings.advanced.graphicsCaches.detail",
                "settings.advanced.graphicsCaches.button") {
                CrosswireApp.killBottles()
                CrosswireApp.wipeShaderCaches()
            }
            Divider().padding(.vertical, 12)
            actionRow("uninstall.menu", "trash.slash", destructive: true) {
                CrosswireApp.confirmUninstall()
            }
        }
    }

    /// A titled row with a sentence saying what the button actually does.
    ///
    /// These were five bare buttons. "Clear Shader Caches" tells someone who
    /// already knows what a shader cache is nothing they need, and everyone
    /// else nothing at all. Every row now says when you would want it.
    ///
    /// Diagnostics and Quit All also live in the menu bar, under Help and in
    /// the app menu. That is deliberate: the menu is where you reach for them
    /// mid-problem, and this is where you find out what they are.
    @ViewBuilder
    private func row(
        _ title: LocalizedStringKey,
        _ detail: LocalizedStringKey,
        _ button: LocalizedStringKey,
        first: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                Text(detail)
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(button, action: action)
                .buttonStyle(CrosswireButtonStyle(kind: .secondary))
                .layoutPriority(1)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            if !first {
                Rectangle().fill(CrosswireTheme.surfaceStroke).frame(height: 0.5)
            }
        }
    }

    @ViewBuilder
    private func actionRow(
        _ title: LocalizedStringKey,
        _ systemImage: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 16)
                Text(title)
                Spacer()
            }
        }
        .buttonStyle(CrosswireButtonStyle(kind: destructive ? .destructive : .secondary, fillWidth: true))
            }
}
