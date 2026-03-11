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
