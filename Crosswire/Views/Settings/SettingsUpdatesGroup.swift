//
//  SettingsUpdatesGroup.swift
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

/// Updates section: the two auto-check toggles (distinct UserDefaults keys —
/// never collapse to one; the second covers the Windows-compatibility layer and
/// avoids the word "engine" per the naming rule), plus the opt-in **beta channel**.
///
/// Switching channels is gated: flipping the beta toggle stages a *pending* change
/// and shows a confirm (the swap re-downloads ~200 MB of compatibility layer). On
/// confirm we commit + re-provision the engine for the new channel; on cancel the
/// toggle snaps back. Leaving beta from a beta build also force-reinstalls the
/// latest stable so the user actually returns to stable (the back-out safety net).
struct SettingsUpdatesGroup: View {
    @AppStorage("SUEnableAutomaticChecks") private var automaticChecksEnabled = true
    @AppStorage("checkEngineUpdates") var checkEngineUpdates = true
    @AppStorage(UpdateChannel.defaultsKey) private var betaChannel = false
    let updater: SPUUpdater?

    /// The channel value the toggle is *trying* to become, pending confirmation.
    @State private var pendingBeta: Bool?

    var body: some View {
        Form {
            Toggle("Check for updates automatically", isOn: automaticChecks)
                .tint(CrosswireTheme.accent)
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Toggle("Automatically check for Windows compatibility updates", isOn: $checkEngineUpdates)
                .tint(CrosswireTheme.accent)
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Receive beta updates", isOn: betaToggle)
                    .tint(CrosswireTheme.accent)
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                Text("Beta updates may be less stable. Switching channels downloads about 200 MB. "
                    + "Leaving beta also reinstalls the latest stable app.")
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let updater {
                SparkleView(updater: updater)
                    .buttonStyle(CrosswireButtonStyle(kind: .secondary))
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(confirmTitle, isPresented: confirmShown, titleVisibility: .visible) {
            Button(pendingBeta == true ? "Switch to Beta" : "Switch to Stable") { commitChannelChange() }
            Button("Cancel", role: .cancel) { pendingBeta = nil }
        } message: {
            Text(confirmMessage)
        }
    }

    private var automaticChecks: Binding<Bool> {
        Binding(get: { automaticChecksEnabled },
                set: { value in
                    automaticChecksEnabled = value
                    updater?.automaticallyChecksForUpdates = value
                })
    }

    /// Reflects the committed channel; flipping stages `pendingBeta`. On cancel
    /// `pendingBeta` clears and the toggle reads back the real channel (snaps back).
    private var betaToggle: Binding<Bool> {
        Binding(
            get: { pendingBeta ?? betaChannel },
            set: { pendingBeta = ($0 == betaChannel) ? nil : $0 }
        )
    }

    private var confirmShown: Binding<Bool> {
        Binding(
            get: { pendingBeta != nil && pendingBeta != betaChannel },
            set: { if !$0 { pendingBeta = nil } }
        )
    }

    private var confirmTitle: String {
        pendingBeta == true ? "Switch to the beta channel?" : "Leave the beta channel?"
    }

    private var confirmMessage: String {
        let base = "This downloads about 200 MB of support files."
        return pendingBeta == false
            ? base + " It also reinstalls you onto the latest stable build."
            : base
    }

    @MainActor
    private func commitChannelChange() {
        guard let target = pendingBeta else { return }
        let leavingBeta = betaChannel && !target
        betaChannel = target
        pendingBeta = nil
        // Re-provision the engine for the new channel (ContentView handles it).
        NotificationCenter.default.post(name: .crosswireReprovisionEngine, object: nil)
        // Leaving beta from a beta build: force the app back to the latest stable.
        let onBetaBuild = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            .localizedCaseInsensitiveContains("beta")
        if leavingBeta, onBetaBuild {
            CrosswireUpdaterDelegate.shared.reinstallLatestStable()
        }
    }
}
