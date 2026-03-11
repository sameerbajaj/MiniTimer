//
//  StopwatchViewModel.swift
//  MiniTimer
//

import SwiftUI
import Observation
import AppKit

@Observable
@MainActor
final class StopwatchViewModel {
    var timeElapsed: TimeInterval = 0
    var isRunning = false
    var isAlwaysOnTop: Bool = UserDefaults.standard.bool(forKey: "isAlwaysOnTop") {
        didSet {
            UserDefaults.standard.set(isAlwaysOnTop, forKey: "isAlwaysOnTop")
            updateWindowLevel()
        }
    }

    var updateInfo: UpdateInfo?
    var updateAlert: UpdateAlert?
    var updateState: SelfUpdater.State = .idle
    var isCheckingForUpdates = false

    private let selfUpdater = SelfUpdater()
    private var timer: Timer?
    private var accumulatedTime: TimeInterval = 0
    private var startedAt: Date?

    init() {
        DispatchQueue.main.async { [weak self] in
            self?.updateWindowLevel()
        }

        self.updateState = selfUpdater.state
    }

    func toggleTimer() {
        isRunning ? stopTimer() : startTimer()
    }

    func startTimer() {
        guard !isRunning else { return }

        isRunning = true
        startedAt = Date()
        startDisplayTimer()
    }

    func stopTimer() {
        guard isRunning else { return }

        accumulatedTime = currentElapsedTime
        startedAt = nil
        isRunning = false
        invalidateTimer()
        timeElapsed = accumulatedTime
    }

    func reset() {
        accumulatedTime = 0
        startedAt = isRunning ? Date() : nil
        timeElapsed = 0
    }

    func updateWindowLevel() {
        if let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.delegate != nil }) ?? NSApplication.shared.keyWindow {
            window.level = isAlwaysOnTop ? .floating : .normal
        }
    }

    func checkUpdates() {
        Task {
            let result = await UpdateChecker.checkForUpdates()

            await MainActor.run {
                switch result {
                case .updateAvailable(let info):
                    self.updateInfo = info
                case .upToDate:
                    break
                case .failed:
                    break
                }
            }
        }
    }

    func manuallyCheckForUpdates() {
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true
        updateAlert = nil

        Task {
            let result = await UpdateChecker.checkForUpdates()

            await MainActor.run {
                self.isCheckingForUpdates = false

                switch result {
                case .updateAvailable(let info):
                    self.updateInfo = info
                    self.updateAlert = .updateAvailable(version: info.version, downloadURL: info.downloadURL)

                case .upToDate:
                    self.updateAlert = .upToDate

                case .failed(let message):
                    self.updateAlert = .failure(message: message)
                }
            }
        }
    }

    func installAvailableUpdate() {
        guard let updateInfo else {
            updateAlert = .failure(message: "No update is currently available to install.")
            return
        }

        installUpdate(using: updateInfo)
    }

    func installUpdate(from alert: UpdateAlert? = nil) {
        let info: UpdateInfo?

        switch alert {
        case .updateAvailable(let version, let downloadURL):
            info = UpdateInfo(
                version: version,
                buildIdentifier: nil,
                publishedAt: nil,
                downloadURL: downloadURL,
                assetName: downloadURL.lastPathComponent,
                releaseNotesURL: UpdateChecker.releasesPage,
                releaseName: version,
                releaseNotes: nil,
                tagName: version
            )
        default:
            info = updateInfo
        }

        guard let info else {
            updateAlert = .failure(message: "No update package is available.")
            return
        }

        installUpdate(using: info)
    }

    func dismissUpdateAlert() {
        updateAlert = nil
    }

    func openUpdateDownloadInBrowser(from alert: UpdateAlert? = nil) {
        let url: URL?

        switch alert {
        case .updateAvailable(_, let downloadURL):
            url = downloadURL
        default:
            url = updateInfo?.downloadURL
        }

        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    func clearUpdateBanner() {
        updateInfo = nil
    }

    func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedPrimaryTime: String {
        formatTime(timeElapsed)
    }

    var formattedFractionalTime: String {
        let tenths = Int((timeElapsed * 10).rounded(.down)) % 10
        return ".\(tenths)"
    }

    var accessibilityFormattedTime: String {
        let totalSeconds = Int(timeElapsed)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = Int((timeElapsed * 10).rounded(.down)) % 10
        return String(format: "%02d:%02d.%01d", minutes, seconds, tenths)
    }

    var shortHintText: String {
        if isCheckingForUpdates {
            return "Checking for updates…"
        }

        switch updateState {
        case .idle:
            return isRunning ? "Timer is active" : "Ready when you are"
        case .downloading(let progress):
            let percent = Int((progress * 100).rounded())
            return "Downloading update… \(percent)%"
        case .installing:
            return "Installing update…"
        case .failed:
            return "Update failed"
        }
    }

    var updateProgressValue: Double? {
        if case .downloading(let progress) = updateState {
            return progress
        }
        return nil
    }

    var isInstallingUpdate: Bool {
        switch updateState {
        case .downloading, .installing:
            return true
        case .idle, .failed:
            return false
        }
    }

    var updateErrorMessage: String? {
        if case .failed(let message) = updateState {
            return message
        }
        return nil
    }

    var tenthsText: String {
        formattedFractionalTime
    }

    private var currentElapsedTime: TimeInterval {
        accumulatedTime + (startedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func startDisplayTimer() {
        invalidateTimer()

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.timeElapsed = self.currentElapsedTime
            }
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func installUpdate(using info: UpdateInfo) {
        guard !isInstallingUpdate else { return }

        updateAlert = nil
        updateState = .downloading(progress: 0)

        Task {
            await selfUpdater.installUpdate(from: info)

            await MainActor.run {
                self.updateState = selfUpdater.state

                if case .failed(let message) = selfUpdater.state {
                    self.updateAlert = .failure(message: message)
                }
            }
        }
    }
}

enum UpdateAlert: Identifiable, Equatable {
    case upToDate
    case updateAvailable(version: String, downloadURL: URL)
    case failure(message: String)

    var id: String {
        switch self {
        case .upToDate:
            return "upToDate"
        case .updateAvailable(let version, _):
            return "updateAvailable-\(version)"
        case .failure(let message):
            return "failure-\(message)"
        }
    }

    var title: String {
        switch self {
        case .upToDate:
            return "You're up to date"
        case .updateAvailable:
            return "Update available"
        case .failure:
            return "Update failed"
        }
    }

    var message: String {
        switch self {
        case .upToDate:
            return "MiniTimer is already running the latest version available."
        case .updateAvailable(let version, _):
            return "MiniTimer \(version) is available to download and install."
        case .failure(let message):
            return message
        }
    }

    var downloadURL: URL? {
        switch self {
        case .upToDate, .failure:
            return nil
        case .updateAvailable(_, let downloadURL):
            return downloadURL
        }
    }
}
