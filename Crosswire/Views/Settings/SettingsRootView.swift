//
//  SettingsRootView.swift
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

import Sparkle
import SwiftUI

/// Settings, in a Settings window, the way every other Mac app does it.
///
/// This reverses an earlier decision. Settings used to slide in over the
/// library as a full-bleed inline destination, which cost the app three things
/// a standard scene gives for free: ⌘, and the app-menu item without wiring,
/// a window that can sit beside the library instead of hiding it, and the
/// tabbed layout people already know how to read. It also meant the only way
/// to change a setting was to stop looking at your library.
///
/// The tabs are the system's own `TabView` in `.tabBarOnly` form, so the
/// window sizes itself to whichever pane is showing, as a Settings window
/// should.
struct SettingsRootView: View {
    let updater: SPUUpdater?

    var body: some View {
        TabView {
            SettingsGeneralGroup()
                .settingsPane()
                .tabItem { Label("settings.tab.general", systemImage: "gearshape") }
            SettingsUpdatesGroup(updater: updater)
                .settingsPane()
                .tabItem { Label("settings.tab.updates", systemImage: "arrow.triangle.2.circlepath") }
            SettingsPrivacyGroup()
                .settingsPane()
                .tabItem { Label("settings.tab.privacy", systemImage: "lock.shield") }
            SettingsAdvancedGroup()
                .settingsPane()
                .tabItem { Label("settings.tab.advanced", systemImage: "wrench.adjustable") }
        }
        .frame(width: 520)
    }
}

private extension View {
    /// One padding and alignment rule for every pane, so the tabs do not each
    /// invent their own margins.
    func settingsPane() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
    }
}
