import Foundation

enum ReviewSeverity: String, CaseIterable, Identifiable, Codable {
    case error
    case warning
    case info

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Info"
        }
    }
}

enum ReviewDiffLineKind: String, Codable {
    case added
    case removed
    case context
    case meta
}

struct ReviewDiffLine: Identifiable, Codable {
    let id: UUID
    let kind: ReviewDiffLineKind
    let text: String

    init(id: UUID = UUID(), kind: ReviewDiffLineKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

struct ReviewDiffBlock: Codable {
    let lines: [ReviewDiffLine]
}

struct ReviewFinding: Identifiable, Codable {
    let id: UUID
    let severity: ReviewSeverity
    let file: String?
    let line: Int?
    let lineEnd: Int?
    let typeRaw: String?
    let typeDisplay: String
    let appliesTo: String?
    let commentText: String
    let proposedFixEmoji: String?
    let proposedFixTitle: String?
    let proposedFix: ReviewDiffBlock?
    let aiPrompt: String?

    init(
        id: UUID = UUID(),
        severity: ReviewSeverity,
        file: String?,
        line: Int?,
        lineEnd: Int?,
        typeRaw: String?,
        typeDisplay: String,
        appliesTo: String?,
        commentText: String,
        proposedFixEmoji: String? = nil,
        proposedFixTitle: String? = nil,
        proposedFix: ReviewDiffBlock?,
        aiPrompt: String?
    ) {
        self.id = id
        self.severity = severity
        self.file = file
        self.line = line
        self.lineEnd = lineEnd
        self.typeRaw = typeRaw
        self.typeDisplay = typeDisplay
        self.appliesTo = appliesTo
        self.commentText = commentText
        self.proposedFixEmoji = proposedFixEmoji
        self.proposedFixTitle = proposedFixTitle
        self.proposedFix = proposedFix
        self.aiPrompt = aiPrompt
    }
}

enum ReviewStatus {
    case idle
    case running
    case completed(Int32)
    case failed(String)
}

enum ReviewPhase: String, CaseIterable, Identifiable, Codable {
    case starting
    case connecting
    case settingUp
    case analyzing
    case reviewing
    case complete

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .starting: return "Starting"
        case .connecting: return "Connecting"
        case .settingUp: return "Setting up"
        case .analyzing: return "Analyzing"
        case .reviewing: return "Reviewing"
        case .complete: return "Complete"
        }
    }
}
