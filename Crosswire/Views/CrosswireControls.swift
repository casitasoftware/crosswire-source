//
//  CrosswireControls.swift
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

/// Shared native styles retain the system focus, contrast and press behavior.
struct CrosswireButtonStyle: PrimitiveButtonStyle {
    enum Kind {
        case secondary
        case destructive
        case plain
    }

    var kind: Kind = .secondary
    /// Expand to fill the available width (e.g. the detail view's equal-width
    /// action row, or full-width maintenance rows).
    var fillWidth: Bool = false
    /// Optional system tint for secondary actions.
    var tint: Color?

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if kind == .plain {
            nativeButton(configuration).buttonStyle(.borderless)
        } else {
            nativeButton(configuration).buttonStyle(.bordered)
        }
    }

    private func nativeButton(_ configuration: Configuration) -> some View {
        Button(role: kind == .destructive ? .destructive : configuration.role, action: configuration.trigger) {
            configuration.label.frame(maxWidth: fillWidth ? .infinity : nil)
        }
        .tint(tint)
    }

}

/// A native prominent button, shared by install and launch actions.
struct PrimaryCTAButtonStyle: PrimitiveButtonStyle {
    enum Size { case compact, prominent }
    var size: Size = .compact
    /// Expand to fill the available width (the detail view's full-width Launch).
    var fillWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.frame(maxWidth: fillWidth ? .infinity : nil)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(size == .prominent ? .large : .regular)
    }
}

/// The small square selection checkbox used by the runtime sheets — accent
/// fill + white check when selected, a quiet outline otherwise. One control so
/// both sheets render an identical, on-brand checkbox.
struct RuntimeCheckbox: View {
    let selected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(selected ? CrosswireTheme.accent : Color.primary.opacity(0.25),
                              lineWidth: 1.25)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(selected ? CrosswireTheme.accent : Color.clear)
                )
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CrosswireTheme.textOnAccent)
            }
        }
        .frame(width: 16, height: 16)
    }
}

extension View {
    /// The shared small-caps section-header treatment (LIBRARY / SETTINGS /
    /// RECOMMENDED …): 11pt semibold, uppercased, tracked, secondary tone.
    /// One modifier so every section label matches instead of re-hardcoding
    /// the font + textCase + tracking at each call site.
    func cwSectionHeader() -> some View {
        self
            .font(CrosswireTheme.Typography.sectionHeader)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(CrosswireTheme.textSecondary)
    }
}

/// The shared "‹ Library" back bar at the top-left of every inline panel
/// (Settings + per-app detail). Both panels are slide-in navigation
/// destinations over the library, so they must exit identically.
struct InlinePanelBackBar: View {
    var action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Library")
                }
            }
            .buttonStyle(CrosswireButtonStyle(kind: .plain, tint: CrosswireTheme.accent))
            .keyboardShortcut(.cancelAction)
            .help("Back to Library")
            .accessibilityLabel("Back to Library")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
