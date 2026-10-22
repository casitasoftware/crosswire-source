//
//  CrosswireUpdateController.swift
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
import Sparkle
import SwiftUI

/// Owns the UI driver for as long as Sparkle can call it.
@MainActor
final class CrosswireUpdateController {
    let updater: SPUUpdater
    private let userDriver: CrosswireUpdateUserDriver

    init() {
        userDriver = CrosswireUpdateUserDriver(hostBundle: .main, delegate: nil)
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                             userDriver: userDriver, delegate: CrosswireUpdaterDelegate.shared)
    }

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        do {
            try updater.start()
            // Sparkle otherwise waits for the scheduled interval, even on launch.
            if updater.automaticallyChecksForUpdates {
                updater.checkForUpdatesInBackground()
            }
        } catch {
            NSLog("Crosswire updater failed to start: %@", error.localizedDescription)
        }
    }
}

/// Changes the choices, while Sparkle owns downloading, verification and installation.
@MainActor
final class CrosswireUpdateUserDriver: SPUStandardUserDriver, NSWindowDelegate {
    private var installWhenQuitting = false
    private var prompt: NSWindow?
    private var answer: ((Bool?) -> Void)?

    override func showUpdateFound(with appcastItem: SUAppcastItem,
                                  state: SPUUserUpdateState,
                                  reply: @escaping (SPUUserUpdateChoice) -> Void) {
        super.dismissUpdateInstallation()
        if appcastItem.isInformationOnlyUpdate {
            present(message: "View the update details to continue.", primary: "View Details", secondary: "Later") {
                if $0 == true, let url = appcastItem.infoURL { NSWorkspace.shared.open(url) }
                reply(.dismiss)
            }
            return
        }
        var message = "Install now and restart Crosswire, or install when you quit."
        if appcastItem.itemDescriptionFormat == "plain-text", let notes = appcastItem.itemDescription {
            message += "\n\n" + notes
        }
        present(message: message, primary: "Update and Restart", secondary: "Install When I Quit") { [weak self] now in
            guard let now else {
                reply(.dismiss)
                return
            }
            self?.installWhenQuitting = !now
            // Before installation is staged, both choices must download and prepare it.
            reply(!now && state.stage == .installing ? .dismiss : .install)
        }
    }

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        super.dismissUpdateInstallation()
        reply(installWhenQuitting ? .dismiss : .install)
    }

    override func dismissUpdateInstallation() {
        answer = nil
        prompt?.delegate = nil
        prompt?.close()
        prompt = nil
        super.dismissUpdateInstallation()
    }

    func windowWillClose(_ notification: Notification) {
        // Dismissal does not authorize a download or installation.
        respond(now: nil)
    }

    private func respond(now: Bool?) {
        let callback = answer
        answer = nil
        prompt?.delegate = nil
        prompt?.close()
        prompt = nil
        callback?(now)
    }

    private func present(message: String, primary: String, secondary: String, answer: @escaping (Bool?) -> Void) {
        self.answer = answer
        let window = UpdatePromptWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Software Update"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: UpdatePromptView(
            message: message, primary: primary, secondary: secondary,
            choose: { [weak self] in self?.respond(now: $0) }))
        window.center()
        prompt = window
        window.makeKeyAndOrderFront(nil)
    }
}

private struct UpdatePromptView: View {
    let message: String
    let primary: String
    let secondary: String
    let choose: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Crosswire Update Available", systemImage: "arrow.down.circle")
                .font(.headline)
            ScrollView {
                Text(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button(secondary) { choose(false) }
                Button(primary) { choose(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 240)
    }
}

/// Escape has the same safe behavior as the close button.
private final class UpdatePromptWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
