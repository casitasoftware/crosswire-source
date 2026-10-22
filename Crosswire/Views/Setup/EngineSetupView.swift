//
//  EngineSetupView.swift
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
import CrosswireKit

struct EngineSetupView: View {
    @State private var phase: Phase = .fetchingManifest
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadStartTime: Date?
    @State private var errorMessage: String?
    @State private var isUpdate = false
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

    enum Phase: Equatable {
        case fetchingManifest
        case downloading
        case verifying
        case installing
        case done
    }

    var body: some View {
        VStack(spacing: 0) {
            heading
                .padding(.top, 8)
            Spacer(minLength: 12)
            stageContent
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .frame(width: 420, height: 320)
        .onAppear { startSetup() }
    }

    private var headingKey: LocalizedStringKey {
        guard phase == .downloading else { return "setup.engine.install" }
        return isUpdate ? "setup.engine.update" : "setup.engine.download"
    }

    /// What is happening right now, in plain words. The spinner alone says
    /// nothing, and the step before the download can take a while on a slow
    /// connection.
    private var statusText: LocalizedStringKey {
        switch phase {
        case .fetchingManifest: return "Checking what to download"
        case .downloading: return "Downloading"
        case .verifying: return "Checking the download"
        case .installing: return "Installing"
        case .done: return "Support files are ready"
        }
    }

    /// Cancel is offered only while nothing on disk has changed. Once the
    /// download is verified, the installed copy is replaced, and stopping
    /// halfway would leave nothing usable.
    private var canCancel: Bool {
        phase == .fetchingManifest || phase == .downloading
    }

    @ViewBuilder
    private var heading: some View {
        VStack(spacing: 6) {
            Text(headingKey)
                .font(CrosswireTheme.Typography.title)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Text("setup.engine.install.subtitle")
                .font(CrosswireTheme.Typography.entryMeta)
                .foregroundStyle(CrosswireTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        if let errorMessage {
            errorBlock(errorMessage)
        } else if phase == .done {
            successHalo
        } else if phase == .downloading && totalBytes > 0 {
            downloadProgress
        } else {
            spinnerHalo
        }
    }

    @ViewBuilder
    private var spinnerHalo: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .frame(width: 56, height: 56)
            Text(statusText)
                .font(CrosswireTheme.Typography.entryMeta)
                .foregroundStyle(CrosswireTheme.textSecondary)
            cancelButton
        }
    }

    @ViewBuilder
    private var cancelButton: some View {
        if canCancel {
            Button("Cancel") {
                Task { await EngineInstaller.shared.cancel() }
            }
            .controlSize(.regular)
            .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var successHalo: some View {
        ZStack {
            Circle()
                .fill(CrosswireTheme.success.opacity(0.12))
                .frame(width: 96, height: 96)
            Image(systemName: "checkmark")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(CrosswireTheme.success)
        }
        .transition(.scale.combined(with: .opacity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Support files are ready")
    }

    @ViewBuilder
    private func errorBlock(_ message: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CrosswireTheme.danger.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(CrosswireTheme.danger)
            }
            Text(message)
                .foregroundStyle(CrosswireTheme.textPrimary)
                .font(CrosswireTheme.Typography.entryMeta)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            HStack(spacing: 10) {
                Button("setup.quit") { exit(0) }
                    .controlSize(.regular)
                Button("setup.retry") {
                    self.errorMessage = nil
                    startSetup()
                }
                .buttonStyle(.borderedProminent)
                .tint(CrosswireTheme.controlFill)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private var downloadProgress: some View {
        VStack(spacing: 10) {
            ProgressView(value: Double(completedBytes), total: Double(totalBytes))
                .progressViewStyle(.linear)
                .tint(CrosswireTheme.accent)
            HStack(spacing: 6) {
                Text(formatBytes(completedBytes))
                    .foregroundStyle(CrosswireTheme.textPrimary)
                Text("/")
                    .foregroundStyle(CrosswireTheme.textTertiary)
                Text(formatBytes(totalBytes))
                    .foregroundStyle(CrosswireTheme.textSecondary)
                if shouldShowETA() {
                    Text("·")
                        .foregroundStyle(CrosswireTheme.textTertiary)
                    Text(formatRemainingTime())
                        .foregroundStyle(CrosswireTheme.textSecondary)
                }
                Spacer()
            }
            .font(.system(size: 11, design: .monospaced))
            .monospacedDigit()
            cancelButton
                .padding(.top, 6)
        }
    }

    private func startSetup() {
        isUpdate = CrosswireEngine.isEnginePresent()
        phase = .fetchingManifest
        completedBytes = 0
        totalBytes = 0
        downloadSpeed = 0
        downloadStartTime = nil

        Task.detached {
            do {
                // `.onAppear` fires again whenever SwiftUI re-inserts this view.
                // The single-flight guard lives in EngineInstaller because a
                // view-local one dies with the view instance: a re-inserted view
                // would start a second download and race the first one's
                // install. A second caller joins the running install and keeps
                // receiving its progress. #147.
                try await EngineInstaller.shared.install { event in
                    Task { @MainActor in apply(event) }
                }

                await MainActor.run {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                        phase = .done
                    }
                }

                try await Task.sleep(for: .seconds(2))
                await MainActor.run { SetupFlow.finish(path: $path, showSetup: $showSetup) }
            } catch {
                // A cancel is the user's own choice: say what state things are
                // in, offer Retry, and do not report it as a fault.
                let wasCancelled = error is CancellationError
                    || (error as? URLError)?.code == .cancelled
                if !wasCancelled {
                    CrosswireTelemetry.capture(error, context: "engine.setup")
                }
                await MainActor.run {
                    errorMessage = wasCancelled
                        ? "Setup stopped. Windows support is not installed yet."
                        : error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func apply(_ event: EngineInstallEvent) {
        switch event {
        case .fetchingManifest:
            phase = .fetchingManifest

        case let .downloading(written, total):
            if phase != .downloading {
                phase = .downloading
                downloadStartTime = Date()
            }
            let elapsed = Date().timeIntervalSince(downloadStartTime ?? Date())
            if written > 0 && elapsed > 0 {
                downloadSpeed = Double(written) / elapsed
            }
            completedBytes = written
            if total > 0 { totalBytes = total }

        case .verifying:
            phase = .verifying

        case .installed:
            // `.done` is set once install() returns, so a view that joined a
            // running install lands on it too.
            break
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    private func shouldShowETA() -> Bool {
        let elapsed = Date().timeIntervalSince(downloadStartTime ?? Date())
        return elapsed > 5 && completedBytes > 0 && downloadSpeed > 0
    }

    private func formatRemainingTime() -> String {
        let remaining = Double(totalBytes - completedBytes) / downloadSpeed
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(remaining)) ?? ""
    }
}
