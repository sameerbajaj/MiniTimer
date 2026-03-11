//
//  UpdateChecker.swift
//  MiniTimer
//

import Foundation

struct UpdateInfo: Equatable, Sendable {
    let version: String
    let buildIdentifier: String?
    let publishedAt: Date?
    let downloadURL: URL
    let assetName: String
    let releaseNotesURL: URL
    let releaseName: String
    let releaseNotes: String?
    let tagName: String

    var displayVersion: String {
        version.isEmpty ? tagName : version
    }
}

enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(UpdateInfo)
    case upToDate
    case failed(String)
}

enum UpdateChecker {
    static let githubRepo = "sameerbajaj/MiniTimer"
    static let releasesPage = URL(string: "https://github.com/\(githubRepo)/releases")!

    static func check() async -> UpdateInfo? {
        switch await checkForUpdates() {
        case .updateAvailable(let info):
            return info
        case .upToDate, .failed:
            return nil
        }
    }

    static func checkForUpdates() async -> UpdateCheckResult {
        let releasesURL = URL(string: "https://api.github.com/repos/\(githubRepo)/releases")!
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MiniTimer/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failed("Invalid server response.")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return .failed(message(for: httpResponse.statusCode))
            }

            let releases = try JSONDecoder.githubReleases.decode([GitHubRelease].self, from: data)

            guard let candidate = bestInstallableRelease(from: releases) else {
                return .upToDate
            }

            return .updateAvailable(candidate)
        } catch is DecodingError {
            return .failed("The update information could not be read.")
        } catch {
            return .failed("Unable to check for updates. Please try again.")
        }
    }

    static var currentVersion: String {
        let value = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return normalizedVersion(from: value ?? "0")
    }

    static var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private static func bestInstallableRelease(from releases: [GitHubRelease]) -> UpdateInfo? {
        let installable = releases
            .filter { !$0.draft && !$0.prerelease }
            .compactMap { releaseToUpdateInfo($0) }

        guard !installable.isEmpty else {
            return nil
        }

        let latest = installable.sorted { lhs, rhs in
            isPreferredUpdate(lhs, rhs)
        }.first!

        if isNewerThanCurrent(latest) {
            return latest
        }

        return nil
    }

    private static func releaseToUpdateInfo(_ release: GitHubRelease) -> UpdateInfo? {
        guard let asset = release.assets.first(where: { isInstallableAssetName($0.name) }),
              let downloadURL = URL(string: asset.browserDownloadURL) else {
            return nil
        }

        let normalized = normalizedVersion(from: release.tagName)
        let fallbackVersion = normalized.isEmpty ? release.tagName.trimmingCharacters(in: .whitespacesAndNewlines) : normalized

        return UpdateInfo(
            version: fallbackVersion,
            buildIdentifier: release.buildIdentifier,
            publishedAt: release.publishedAt,
            downloadURL: downloadURL,
            assetName: asset.name,
            releaseNotesURL: release.htmlURL ?? releasesPage,
            releaseName: release.name?.nilIfBlank ?? fallbackVersion,
            releaseNotes: release.body?.nilIfBlank,
            tagName: release.tagName
        )
    }

    nonisolated private static func isPreferredUpdate(_ lhs: UpdateInfo, _ rhs: UpdateInfo) -> Bool {
        if isVersion(lhs.version, newerThan: rhs.version) { return true }
        if isVersion(rhs.version, newerThan: lhs.version) { return false }

        if let leftDate = lhs.publishedAt, let rightDate = rhs.publishedAt, leftDate != rightDate {
            return leftDate > rightDate
        }

        let leftBuild = numericBuildValue(lhs.buildIdentifier)
        let rightBuild = numericBuildValue(rhs.buildIdentifier)
        if leftBuild != rightBuild {
            return leftBuild > rightBuild
        }

        return lhs.displayVersion.localizedStandardCompare(rhs.displayVersion) == .orderedDescending
    }

    private static func isNewerThanCurrent(_ info: UpdateInfo) -> Bool {
        if isVersion(info.version, newerThan: currentVersion) {
            return true
        }

        if isVersion(currentVersion, newerThan: info.version) {
            return false
        }

        let currentBuildValue = numericBuildValue(currentBuild)
        let releaseBuild = numericBuildValue(info.buildIdentifier)
        if releaseBuild > currentBuildValue {
            return true
        }

        return false
    }

    private static func isInstallableAssetName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.hasSuffix(".dmg") || lowercased.hasSuffix(".zip")
    }

    private static func normalizedVersion(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let strippedV = trimmed.replacingOccurrences(
            of: #"^[vV]"#,
            with: "",
            options: .regularExpression
        )

        let semanticPrefix = strippedV.captureFirstMatch(for: #"^\d+(?:\.\d+){0,3}"#)
        return semanticPrefix ?? strippedV
    }

    private static func numericBuildValue(_ raw: String?) -> Int {
        guard let raw else { return 0 }
        let digits = raw.filter(\.isNumber)
        return Int(digits) ?? 0
    }

    private static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }

        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0

            if l > r { return true }
            if l < r { return false }
        }

        return false
    }

    private static func message(for statusCode: Int) -> String {
        switch statusCode {
        case 403:
            return "GitHub rate-limited the update check. Please try again in a bit."
        case 404:
            return "The releases feed could not be found."
        default:
            return "Update check failed with server code \(statusCode)."
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let htmlURL: URL?
    let publishedAt: Date?
    let assets: [GitHubReleaseAsset]

    var buildIdentifier: String? {
        let candidates = [
            tagName.captureFirstMatch(for: #"\+([0-9A-Za-z\.\-_]+)$"#),
            name?.captureFirstMatch(for: #"\+([0-9A-Za-z\.\-_]+)$"#),
            body?.captureFirstMatch(for: #"(?im)^build\s*:\s*([0-9A-Za-z\.\-_]+)\s*$"#)
        ]

        return candidates
            .compactMap { $0 }
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case draft
        case prerelease
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private extension JSONDecoder {
    static var githubReleases: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func captureFirstMatch(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range) else {
            return nil
        }

        let captureRange: NSRange
        if match.numberOfRanges > 1 {
            captureRange = match.range(at: 1)
        } else {
            captureRange = match.range(at: 0)
        }

        guard let swiftRange = Range(captureRange, in: self) else {
            return nil
        }

        return String(self[swiftRange])
    }
}
