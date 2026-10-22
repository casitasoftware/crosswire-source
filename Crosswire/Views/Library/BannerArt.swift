//
//  BannerArt.swift
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
import CrosswireKit

/// Shared machinery for `TileArtView` and `HeroArtView`: resolving a rendered
/// banner for a bottle's candidate `.exe`s at a given pixel size.

/// Identifies one banner request: which exe candidates to try, at what size.
///
/// The size is in PIXELS, not points: `BannerRenderer` renders exactly the
/// size it is given, so passing a view's point size produced half-resolution
/// art on a Retina display. Callers pass their point size and the display
/// scale. Rounded to whole pixels so sub-pixel layout jitter across redraws
/// doesn't retrigger a render `BannerRenderer` would cache identically anyway.
struct BannerRequestKey: Equatable {
    let urls: [URL]
    let width: Int
    let height: Int

    init(urls: [URL], size: CGSize, scale: CGFloat) {
        self.urls = urls
        self.width = Int((size.width * scale).rounded())
        self.height = Int((size.height * scale).rounded())
    }

    var pixelSize: CGSize { CGSize(width: width, height: height) }
}

/// Tries the request's candidate `.exe`s in order and returns the first
/// rendered banner. Mirrors `AppIcon`'s fallback chain so a title without a
/// usable icon on its primary exe still gets one from a secondary program.
///
/// Uses the URLs captured in `key`, not a fresh read of the bottle: the task
/// that runs this is keyed on those URLs, so reading them again could try a
/// different set from the one the task was started for.
///
/// Retries with backoff while nothing renders. An install can still be
/// writing an exe when the candidate list first includes it, and a partly
/// written file has no readable icon. The URL does not change when the file
/// finishes, so the task is not restarted, and the tile kept its placeholder
/// until the view was rebuilt. Gives up after roughly half a minute.
@MainActor
func resolveBanner(for key: BannerRequestKey) async -> NSImage? {
    for delay in bannerRetryDelays {
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
        if Task.isCancelled { return nil }
        for url in key.urls {
            if let banner = await BannerRenderer.banner(forExe: url, size: key.pixelSize) {
                return banner
            }
            if Task.isCancelled { return nil }
        }
    }
    return nil
}

/// Seconds to wait before each attempt. The first is immediate.
let bannerRetryDelays: [Double] = [0, 1, 2, 4, 8, 15]
