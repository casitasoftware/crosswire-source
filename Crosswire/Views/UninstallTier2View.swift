//
//  UninstallTier2View.swift
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

import CrosswireKit
import SwiftUI

/// Stage two of uninstalling: the installed apps themselves.
///
/// Deliberately harder to reach and harder to confirm than stage one. Stage
/// one deletes what Crosswire downloaded, which it can fetch again. This
/// deletes games and their save data, which nobody can get back, so it needs
/// an explicit acknowledgement before the destructive button will even enable,
/// and keeping is the default.
///
/// Every app is listed with its own size rather than just a combined total. A
/// total answers "how much space", but the question people actually have at
/// this point is "wait, what is in here", and a list of names without sizes
/// does not answer it either.
struct UninstallTier2View: View {
    let bottles: [Bottle]
    let onDecision: (Bool) -> Void

    @State private var acknowledged = false
    @State private var sizes: [URL: Int64] = [:]
    @State private var sizesLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("uninstall.apps.title")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CrosswireTheme.textPrimary)
                Text("uninstall.apps.message")
                    .font(.system(size: 12))
                    .foregroundStyle(CrosswireTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            appList

            Text(sizeSummary)
                .font(.system(size: 11))
                .foregroundStyle(CrosswireTheme.textSecondary)

            Toggle(isOn: $acknowledged) {
                Text("uninstall.apps.acknowledge")
                    .font(.system(size: 12))
                    .foregroundStyle(CrosswireTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("uninstall.apps.keep") { onDecision(false) }
                    .buttonStyle(CrosswireButtonStyle(kind: .secondary))
                    .keyboardShortcut(.defaultAction)
                Button("uninstall.apps.delete") { onDecision(true) }
                    .buttonStyle(CrosswireButtonStyle(kind: .destructive))
                    .disabled(!acknowledged)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task { await measure() }
    }

    private var appList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(bottles.enumerated()), id: \.element.id) { index, bottle in
                    HStack(spacing: 12) {
                        Text(bottle.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(CrosswireTheme.textPrimary)
                        Spacer(minLength: 8)
                        Text(sizeText(for: bottle))
                            .monospacedDigit()
                            .foregroundStyle(CrosswireTheme.textSecondary)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle().fill(CrosswireTheme.surfaceStroke).frame(height: 0.5)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CrosswireTheme.surface)
        )
    }

    private func sizeText(for bottle: Bottle) -> String {
        guard let bytes = sizes[bottle.url] else {
            // A dash once measuring is done and the folder could not be read,
            // rather than a zero that reads as "this one is empty".
            return sizesLoaded ? "-" : String(localized: "uninstall.apps.measuring")
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var sizeSummary: String {
        guard sizesLoaded else { return String(localized: "uninstall.apps.measuring") }
        let total = sizes.values.reduce(0, +)
        return UninstallSizeSummary.summary(totalBytes: total, appCount: bottles.count)
    }

    /// Measures every app once, off the main actor. `du` walks the whole tree,
    /// so on a library of large games this takes long enough that the sheet
    /// has to open first and fill in after.
    private func measure() async {
        let urls = bottles.map(\.url)
        let measured = await Task.detached(priority: .utility) { () -> [URL: Int64] in
            var result: [URL: Int64] = [:]
            for url in urls {
                if let size = BottleDiskUsage.approximateSize(of: url) { result[url] = size }
            }
            return result
        }.value
        sizes = measured
        sizesLoaded = true
    }
}
