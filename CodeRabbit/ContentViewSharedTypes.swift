//
//  ContentViewSharedTypes.swift
//  CodeRabbit
//

import Foundation

enum ReviewSelection: Hashable {
    case current
    case history(UUID)
}

enum ReviewOutputMode: String {
    case full
    case promptOnly
}

enum ComparisonBaseMode: String {
    case automatic
    case baseBranch
    case baseCommit
}

enum SidebarPrimarySection: String, CaseIterable, Identifiable {
    case newReview
    case history

    var id: String { rawValue }
}

struct HistoryFolderGroup: Identifiable {
    let folderPath: String
    let items: [ReviewHistoryItem]

    var id: String {
        folderPath
    }
}

struct FindingTypeCounts {
    let potentialIssues: Int
    let nitpicks: Int
    let refactorSuggestions: Int
    let uncategorized: Int

    var categorizedTotal: Int {
        potentialIssues + nitpicks + refactorSuggestions
    }
}

struct AppUpdateInfo: Equatable {
    let currentVersion: String
    let latestVersion: String
    let releaseURL: URL
    let directDownloadURL: URL?
    let publishedAt: Date?
}

enum AppUpdateCheckResult: Equatable {
    case updateAvailable(AppUpdateInfo)
    case upToDate(currentVersion: String, latestVersion: String)
    case failed(message: String)
}

enum AppUpdateService {
    private static let repositoryOwner = "GioPalusa"
    private static let repositoryName = "codeRabbitUI"
    private static let fallbackVersion = "0.0.0"

    static var currentInstalledVersion: String {
        let rawValue = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? fallbackVersion
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallbackVersion : trimmed
    }

    static var currentInstalledVersionLabel: String {
        let buildNumber = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if buildNumber.isEmpty {
            return currentInstalledVersion
        }
        return "\(currentInstalledVersion) (\(buildNumber))"
    }

    static func checkForUpdates() async -> AppUpdateCheckResult {
        guard let apiURL = URL(string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases/latest") else {
            return .failed(message: "Unable to build update endpoint URL.")
        }

        var request = URLRequest(url: apiURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CodeRabbitUI/\(currentInstalledVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failed(message: "Unable to verify update status.")
            }

            guard httpResponse.statusCode == 200 else {
                return .failed(message: updateErrorMessage(forHTTPStatus: httpResponse.statusCode))
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let latestRelease = try decoder.decode(GitHubLatestRelease.self, from: data)

            let currentVersion = normalizedVersion(currentInstalledVersion)
            let latestVersion = normalizedVersion(latestRelease.tagName)
            guard !latestVersion.isEmpty else {
                return .failed(message: "Latest release is missing a valid version tag.")
            }

            if isVersion(latestVersion, newerThan: currentVersion) {
                let dmgDownloadURL = latestRelease.assets
                    .first(where: { $0.name.lowercased().hasSuffix(".dmg") })?
                    .browserDownloadURL

                return .updateAvailable(
                    AppUpdateInfo(
                        currentVersion: currentInstalledVersion,
                        latestVersion: latestVersion,
                        releaseURL: latestRelease.htmlURL,
                        directDownloadURL: dmgDownloadURL,
                        publishedAt: latestRelease.publishedAt
                    )
                )
            }

            return .upToDate(currentVersion: currentInstalledVersion, latestVersion: latestVersion)
        } catch {
            return .failed(message: "Update check failed: \(error.localizedDescription)")
        }
    }

    private static func updateErrorMessage(forHTTPStatus statusCode: Int) -> String {
        switch statusCode {
        case 403:
            return "GitHub API rate limit reached. Try again in a little while."
        case 404:
            return "No public releases found for this repository."
        default:
            return "Unable to check for updates (HTTP \(statusCode))."
        }
    }

    private static func normalizedVersion(_ rawVersion: String) -> String {
        var version = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.lowercased().hasPrefix("v"), version.count > 1 {
            version.removeFirst()
        }
        return version
    }

    private static func isVersion(_ candidateVersion: String, newerThan installedVersion: String) -> Bool {
        let candidateComponents = versionComponents(from: candidateVersion)
        let installedComponents = versionComponents(from: installedVersion)
        let maxCount = max(candidateComponents.count, installedComponents.count)
        guard maxCount > 0 else {
            return candidateVersion.compare(installedVersion, options: .numeric) == .orderedDescending
        }

        for index in 0..<maxCount {
            let candidatePart = index < candidateComponents.count ? candidateComponents[index] : 0
            let installedPart = index < installedComponents.count ? installedComponents[index] : 0
            if candidatePart != installedPart {
                return candidatePart > installedPart
            }
        }

        return false
    }

    private static func versionComponents(from version: String) -> [Int] {
        let normalized = normalizedVersion(version)
        guard !normalized.isEmpty else { return [] }

        return normalized.split(separator: ".").map { segment in
            let digits = segment.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }

    private struct GitHubLatestRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let publishedAt: Date?
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case publishedAt = "published_at"
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}
