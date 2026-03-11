import Foundation
import AppKit
@MainActor
final class SelfUpdater: NSObject {
    enum State: Equatable {
        case idle
        case downloading(progress: Double)
        case installing
        case failed(String)
    }

    struct InstallationContext {
        let appName: String
        let runningAppURL: URL
        let parentDirectoryURL: URL
        let downloadDirectoryURL: URL
        let downloadedDMGURL: URL
        let mountedVolumeURL: URL
        let mountedAppURL: URL
        let stagedAppURL: URL
    }

    var state: State = .idle
    var latestDownloadedFileURL: URL?

    private var downloadContinuation: CheckedContinuation<URL, Error>?
    private var activeDownloadTask: URLSessionDownloadTask?
    private let session: URLSession

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 30
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        super.init()

        session.configuration.waitsForConnectivity = false
    }

    func installUpdate(from updateInfo: UpdateInfo) async {
        guard case .idle = state else { return }

        do {
            let context = try makeContext(for: updateInfo)
            let downloadedDMGURL = try await downloadDMG(from: updateInfo.downloadURL, into: context.downloadDirectoryURL)
            latestDownloadedFileURL = downloadedDMGURL

            state = .installing

            let mountedVolumeURL = try mountDMG(at: downloadedDMGURL)
            let mountedAppURL = try findAppBundle(in: mountedVolumeURL, appName: context.appName)
            let stagedAppURL = try stageAppForReplacement(
                mountedAppURL: mountedAppURL,
                appName: context.appName,
                parentDirectoryURL: context.parentDirectoryURL
            )

            try adHocSignApp(at: stagedAppURL)
            try replaceRunningApp(with: stagedAppURL, at: context.runningAppURL)
            try detachDMG(at: mountedVolumeURL)
            try? cleanupDownloadArtifacts(in: context.downloadDirectoryURL)

            relaunchAndTerminate(appURL: context.runningAppURL)
        } catch {
            state = .failed(SelfUpdaterError.wrap(error).localizedDescription)
        }
    }

    func reset() {
        guard case .installing = state else {
            state = .idle
            return
        }
    }

    private func makeContext(for updateInfo: UpdateInfo) throws -> InstallationContext {
        guard let runningAppURL = Bundle.main.bundleURL.standardizedFileURL.removingSymlinkInPathComponents(),
              runningAppURL.pathExtension == "app" else {
            throw SelfUpdaterError.unableToLocateRunningApp
        }

        let appName = runningAppURL.deletingPathExtension().lastPathComponent
        let parentDirectoryURL = runningAppURL.deletingLastPathComponent()

        guard FileManager.default.isWritableFile(atPath: parentDirectoryURL.path) else {
            throw SelfUpdaterError.installLocationNotWritable(parentDirectoryURL.path)
        }

        let downloadDirectoryURL = try SelfUpdater.downloadDirectoryURL(appName: appName)
        let downloadedDMGURL = downloadDirectoryURL.appendingPathComponent("\(appName)-update.dmg")
        let mountedVolumeURL = URL(fileURLWithPath: "/tmp")
        let mountedAppURL = mountedVolumeURL.appendingPathComponent("\(appName).app")
        let stagedAppURL = parentDirectoryURL.appendingPathComponent(".\(appName)-update-staging.app")

        return InstallationContext(
            appName: appName,
            runningAppURL: runningAppURL,
            parentDirectoryURL: parentDirectoryURL,
            downloadDirectoryURL: downloadDirectoryURL,
            downloadedDMGURL: downloadedDMGURL,
            mountedVolumeURL: mountedVolumeURL,
            mountedAppURL: mountedAppURL,
            stagedAppURL: stagedAppURL
        )
    }

    private static func downloadDirectoryURL(appName: String) throws -> URL {
        let cachesDirectory = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directory = cachesDirectory.appendingPathComponent("\(appName)-Update", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func downloadDMG(from remoteURL: URL, into directory: URL) async throws -> URL {
        state = .downloading(progress: 0)

        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destinationURL = directory.appendingPathComponent(remoteURL.lastPathComponent.isEmpty ? "update.dmg" : remoteURL.lastPathComponent)
        try? FileManager.default.removeItem(at: destinationURL)

        return try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 60 * 30

            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            let task = session.downloadTask(with: remoteURL)
            task.taskDescription = destinationURL.path

            self.activeDownloadTask = task
            task.resume()
        }
    }

    private func mountDMG(at dmgURL: URL) throws -> URL {
        let plistData = try runProcess(
            launchPath: "/usr/bin/hdiutil",
            arguments: [
                "attach",
                dmgURL.path,
                "-nobrowse",
                "-readonly",
                "-mountrandom",
                "/tmp",
                "-plist"
            ]
        )

        guard
            let object = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
            let systemEntities = object["system-entities"] as? [[String: Any]]
        else {
            throw SelfUpdaterError.invalidMountResponse
        }

        for entity in systemEntities {
            if let mountPoint = entity["mount-point"] as? String {
                return URL(fileURLWithPath: mountPoint, isDirectory: true)
            }
        }

        throw SelfUpdaterError.mountPointNotFound
    }

    private func detachDMG(at mountedVolumeURL: URL) throws {
        _ = try runProcess(
            launchPath: "/usr/bin/hdiutil",
            arguments: ["detach", mountedVolumeURL.path, "-force"]
        )
    }

    private func findAppBundle(in mountedVolumeURL: URL, appName: String) throws -> URL {
        let preferredURL = mountedVolumeURL.appendingPathComponent("\(appName).app")
        if FileManager.default.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: mountedVolumeURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        if let firstApp = contents.first(where: { $0.pathExtension == "app" }) {
            return firstApp
        }

        throw SelfUpdaterError.appBundleNotFound
    }

    private func stageAppForReplacement(
        mountedAppURL: URL,
        appName: String,
        parentDirectoryURL: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        let stagedURL = parentDirectoryURL.appendingPathComponent(".\(appName)-update-staging.app")

        try? fileManager.removeItem(at: stagedURL)
        try fileManager.copyItem(at: mountedAppURL, to: stagedURL)

        return stagedURL
    }

    private func adHocSignApp(at appURL: URL) throws {
        do {
            _ = try runProcess(
                launchPath: "/usr/bin/codesign",
                arguments: [
                    "--force",
                    "--deep",
                    "--sign", "-",
                    appURL.path
                ]
            )
        } catch {
            throw SelfUpdaterError.codesignFailed(SelfUpdaterError.wrap(error).localizedDescription)
        }
    }

    private func replaceRunningApp(with stagedAppURL: URL, at runningAppURL: URL) throws {
        do {
            _ = try FileManager.default.replaceItemAt(
                runningAppURL,
                withItemAt: stagedAppURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } catch {
            throw SelfUpdaterError.replaceFailed(SelfUpdaterError.wrap(error).localizedDescription)
        }
    }

    private func cleanupDownloadArtifacts(in directory: URL) throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func relaunchAndTerminate(appURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let escapedAppPath = shellEscape(appURL.path)

        let script = """
        /bin/sh -c '
        target_pid=\(pid)
        tries=100
        while kill -0 "$target_pid" >/dev/null 2>&1 && [ "$tries" -gt 0 ]; do
          sleep 0.1
          tries=$((tries - 1))
        done
        open \(escapedAppPath)
        ' >/dev/null 2>&1 &
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()

        NSApplication.shared.terminate(nil)
    }

    private func runProcess(launchPath: String, arguments: [String]) throws -> Data {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.isEmpty ? stdout : stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SelfUpdaterError.processFailed(
                path: launchPath,
                status: process.terminationStatus,
                message: message?.isEmpty == false ? message! : "Unknown process failure."
            )
        }

        return stdout
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

extension SelfUpdater: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        Task { @MainActor in
            self.state = .downloading(progress: min(max(progress, 0), 1))
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { @MainActor in
            guard let continuation = self.downloadContinuation else { return }
            self.downloadContinuation = nil
            self.activeDownloadTask = nil

            do {
                guard let destinationPath = downloadTask.taskDescription else {
                    throw SelfUpdaterError.downloadDestinationMissing
                }

                let destinationURL = URL(fileURLWithPath: destinationPath)
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }

                try FileManager.default.moveItem(at: location, to: destinationURL)
                continuation.resume(returning: destinationURL)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }

        Task { @MainActor in
            guard let continuation = self.downloadContinuation else { return }
            self.downloadContinuation = nil
            self.activeDownloadTask = nil
            continuation.resume(throwing: SelfUpdaterError.downloadFailed(error.localizedDescription))
        }
    }
}

enum SelfUpdaterError: LocalizedError {
    case unableToLocateRunningApp
    case installLocationNotWritable(String)
    case downloadFailed(String)
    case downloadDestinationMissing
    case invalidMountResponse
    case mountPointNotFound
    case appBundleNotFound
    case codesignFailed(String)
    case replaceFailed(String)
    case processFailed(path: String, status: Int32, message: String)
    case wrapped(Error)

    static func wrap(_ error: Error) -> SelfUpdaterError {
        if let updaterError = error as? SelfUpdaterError {
            return updaterError
        }
        return .wrapped(error)
    }

    var errorDescription: String? {
        switch self {
        case .unableToLocateRunningApp:
            return "MiniTimer could not locate its installed app bundle."
        case .installLocationNotWritable(let path):
            return "MiniTimer can’t install updates because the app’s folder is not writable: \(path)"
        case .downloadFailed(let message):
            return "The update download failed. \(message)"
        case .downloadDestinationMissing:
            return "The update download destination could not be determined."
        case .invalidMountResponse:
            return "The downloaded DMG could not be mounted."
        case .mountPointNotFound:
            return "The mounted DMG did not provide a usable mount point."
        case .appBundleNotFound:
            return "No app bundle was found inside the downloaded DMG."
        case .codesignFailed(let message):
            return "The updated app could not be re-signed. \(message)"
        case .replaceFailed(let message):
            return "MiniTimer could not replace the installed app. \(message)"
        case .processFailed(let path, let status, let message):
            return "Command failed: \(path) exited with status \(status). \(message)"
        case .wrapped(let error):
            return error.localizedDescription
        }
    }
}

private extension URL {
    func removingSymlinkInPathComponents() -> URL? {
        URL(fileURLWithPath: (try? URL(resolvingAliasFileAt: self).path) ?? resolvingSymlinksInPath().path)
    }
}
