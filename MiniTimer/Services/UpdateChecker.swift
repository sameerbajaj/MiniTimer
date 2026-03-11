//
//  UpdateChecker.swift
//  MiniTimer
//

import Foundation

struct UpdateInfo {
    let version: String
    let downloadURL: URL
}

enum UpdateChecker {
    static let githubRepo = "sameerbajaj/MiniTimer" // Placeholder, will update if found
    static let releasesPage = URL(string: "https://github.com/\(githubRepo)/releases")!

    static func check() async -> UpdateInfo? {
        let latestURL = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: latestURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]],
                  let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                  let downloadURLString = dmgAsset["browser_download_url"] as? String,
                  let downloadURL = URL(string: downloadURLString) else {
                return nil
            }
            
            let latestVersion = tagName.replacingOccurrences(of: "v", with: "")
            if isVersion(latestVersion, newerThan: currentVersion) {
                return UpdateInfo(version: latestVersion, downloadURL: downloadURL)
            }
        } catch {
            return nil
        }
        return nil
    }
    
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    
    private static func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let v1Components = v1.split(separator: ".").compactMap { Int($0) }
        let v2Components = v2.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(v1Components.count, v2Components.count) {
            let c1 = i < v1Components.count ? v1Components[i] : 0
            let c2 = i < v2Components.count ? v2Components[i] : 0
            if c1 > c2 { return true }
            if c1 < c2 { return false }
        }
        return false
    }
}
