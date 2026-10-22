//
//  BottleSettings+WindowsUser.swift
//  CrosswireKit
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

import Foundation

extension BottleSettings {
    /// The Windows user name new bottles are created under, in place of the
    /// Mac account name, so a prefix does not carry the owner's login name in
    /// its profile folder, environment or shell folders. Lowercase, following
    /// CrossOver's "crossover".
    public static let defaultWindowsUserName = "crosswire"

    /// Unix environment that pins the Windows user name for every process run
    /// against this bottle.
    ///
    /// The engine names the profile after `USER`. It does not read
    /// `WINEUSERNAME`, which it only exports to the Windows side. Winetricks
    /// builds profile paths from `LOGNAME`, so both are set.
    ///
    /// This must reach EVERY Wine invocation for the bottle: Wine's own
    /// launches (both environment builders in Wine.swift) and both Winetricks
    /// paths. One run without it recreates part of the profile under the Mac
    /// account name while the rest stays put, splitting the user's data across
    /// two profile folders. That is also why an existing bottle is never
    /// switched. Empty for bottles created before this existed.
    public var windowsUserEnvironment: [String: String] {
        guard let name = windowsUserName, !name.isEmpty else { return [:] }
        return ["USER": name, "LOGNAME": name]
    }
}
