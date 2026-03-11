import Foundation

struct ReviewCompletionSummary {
    let findingCount: Int?
    let hasNoFindings: Bool
    let rawLine: String
}

struct ReviewRunErrorInfo {
    let message: String
    let isRateLimit: Bool
    let retryAfter: String?
    let retryAfterSeconds: TimeInterval?
    let occurredAt: Date?
    let rawLine: String
}

struct ReviewParser {
    static let aiAgentVerificationPrefix = "Verify each finding against the current code and only fix it if needed."
    private static let cliUpdateDefaultCommand = "coderabbit update"

    static func parse(from text: String) -> [ReviewFinding] {
        let plainTextFindings = parsePlainTextSections(from: text)
        if !plainTextFindings.isEmpty {
            return plainTextFindings
        }

        if parseRunErrorInfo(from: text) != nil {
            // Runtime/transport errors are presented in dedicated error UI, not as findings.
            return []
        }

        var findings: [ReviewFinding] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            if isOperationalLogLine(trimmedLine) { continue }

            if let parsed = parseGitHubStyle(line) ?? parseBracketStyle(line) {
                findings.append(parsed)
                continue
            }

            if let severity = inferSeverity(from: line) {
                findings.append(
                    ReviewFinding(
                        severity: severity,
                        file: nil,
                        line: nil,
                        lineEnd: nil,
                        typeRaw: nil,
                        typeDisplay: severity.displayName,
                        appliesTo: nil,
                        commentText: line,
                        proposedFix: nil,
                        aiPrompt: nil
                    )
                )
            }
        }

        return findings
    }

    static func combinedAIAgentPrompt(from findings: [ReviewFinding]) -> String? {
        let prompts = findings
            .compactMap { $0.aiPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !prompts.isEmpty else { return nil }

        let combinedBodies = prompts.compactMap { prompt -> String? in
            if let stripped = stripLeadingVerificationPrefix(from: prompt) {
                return stripped.isEmpty ? nil : stripped
            }
            return prompt
        }

        guard !combinedBodies.isEmpty else {
            return aiAgentVerificationPrefix
        }

        return aiAgentVerificationPrefix + "\n\n" + combinedBodies.joined(separator: "\n\n")
    }

    static func parseCLIUpdateCommand(from text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for rawLine in lines {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.lowercased().hasPrefix("run:") else { continue }

            let commandCandidate = String(trimmedLine.dropFirst("Run:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !commandCandidate.isEmpty else { continue }
            return commandCandidate
        }

        if text.localizedCaseInsensitiveContains("new update available") {
            return cliUpdateDefaultCommand
        }

        return nil
    }

    private static func parseGitHubStyle(_ line: String) -> ReviewFinding? {
        // Example: path/to/File.swift:42: warning: message
        let pattern = #"^(.+):(\d+):\s*(error|warning|info):\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsrange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: nsrange) else { return nil }

        guard
            let fileRange = Range(match.range(at: 1), in: line),
            let lineRange = Range(match.range(at: 2), in: line),
            let severityRange = Range(match.range(at: 3), in: line),
            let messageRange = Range(match.range(at: 4), in: line)
        else { return nil }

        let severityText = String(line[severityRange])
        let severityValue = severity(from: severityText) ?? .info
        return ReviewFinding(
            severity: severityValue,
            file: String(line[fileRange]),
            line: Int(String(line[lineRange])),
            lineEnd: nil,
            typeRaw: severityText,
            typeDisplay: severityText,
            appliesTo: nil,
            commentText: String(line[messageRange]),
            proposedFix: nil,
            aiPrompt: nil
        )
    }

    private static func stripLeadingVerificationPrefix(from prompt: String) -> String? {
        let lines = prompt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstNonEmptyIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return nil
        }

        let firstNonEmptyLine = lines[firstNonEmptyIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard firstNonEmptyLine.caseInsensitiveCompare(aiAgentVerificationPrefix) == .orderedSame else {
            return nil
        }

        let remaining = lines.dropFirst(firstNonEmptyIndex + 1).joined(separator: "\n")
        return remaining.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseBracketStyle(_ line: String) -> ReviewFinding? {
        // Example: [WARNING] path/to/File.swift:88 message
        let pattern = #"^\[(ERROR|WARNING|INFO)\]\s+(.+?):(\d+)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsrange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: nsrange) else { return nil }

        guard
            let severityRange = Range(match.range(at: 1), in: line),
            let fileRange = Range(match.range(at: 2), in: line),
            let lineRange = Range(match.range(at: 3), in: line),
            let messageRange = Range(match.range(at: 4), in: line)
        else { return nil }

        let severityText = String(line[severityRange])
        let severityValue = severity(from: severityText) ?? .info
        return ReviewFinding(
            severity: severityValue,
            file: String(line[fileRange]),
            line: Int(String(line[lineRange])),
            lineEnd: nil,
            typeRaw: severityText,
            typeDisplay: severityText,
            appliesTo: nil,
            commentText: String(line[messageRange]),
            proposedFix: nil,
            aiPrompt: nil
        )
    }

    private static func inferSeverity(from line: String) -> ReviewSeverity? {
        let lowered = line.lowercased()
        if lowered.contains("error") { return .error }
        if lowered.contains("warning") { return .warning }
        if lowered.contains("info") || lowered.contains("suggestion") { return .info }
        return nil
    }

    private static func isOperationalLogLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return line.hasPrefix("Starting CodeRabbit review")
            || line == "Connecting to review service"
            || line == "Setting up"
            || line == "Analyzing"
            || line == "Reviewing"
            || line.hasPrefix("Review completed:")
            || line.hasPrefix("Failed to start review:")
            || lowered.hasPrefix("[error]")
            || lowered.contains("rate limit exceeded")
    }

    private static func severity(from text: String) -> ReviewSeverity? {
        switch text.lowercased() {
        case "error": return .error
        case "warning": return .warning
        case "info": return .info
        default: return nil
        }
    }

    private static func parsePlainTextSections(from text: String) -> [ReviewFinding] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var findings: [ReviewFinding] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("File: ") else {
                index += 1
                continue
            }

            let file = String(line.dropFirst("File: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            var lineStart: Int?
            var lineEnd: Int?
            var type: String?
            var appliesTo: String?
            var commentLines: [String] = []
            var proposedFixEmoji: String?
            var proposedFixTitle: String?
            var proposedFixLines: [ReviewDiffLine] = []
            var aiPrompt: String?

            index += 1
            while index < lines.count {
                let current = lines[index]
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)

                if isFindingBoundary(trimmed) {
                    break
                }

                if let parsedLine = parseLineRange(from: trimmed) {
                    lineStart = parsedLine.start
                    lineEnd = parsedLine.end
                    index += 1
                    continue
                }

                if trimmed.hasPrefix("Type: ") {
                    type = String(trimmed.dropFirst("Type: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    index += 1
                    continue
                }

                if trimmed.hasPrefix("Also applies to: ") {
                    appliesTo = String(trimmed.dropFirst("Also applies to: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    index += 1
                    continue
                }

                if trimmed.hasPrefix("Comment:") {
                    let parsed = parseBlockContent(
                        lines: lines,
                        startIndex: index,
                        header: "Comment:",
                        stopWhen: { next in
                            isFindingBoundary(next)
                                || isTerminalReviewLine(next)
                                || next.hasPrefix("Type: ")
                                || next.hasPrefix("Line: ")
                                || next.hasPrefix("Also applies to: ")
                                || next.hasPrefix("Prompt for AI Agent:")
                                || isProposedFixHeader(next)
                        }
                    )
                    commentLines = parsed.contentLines
                    index = parsed.nextIndex
                    continue
                }

                if isProposedFixHeader(trimmed) {
                    proposedFixEmoji = leadingEmoji(from: trimmed)
                    proposedFixTitle = proposedFixTitleFromHeader(trimmed)
                    let parsed = parseBlockContent(
                        lines: lines,
                        startIndex: index,
                        header: nil,
                        stopWhen: { next in
                            isFindingBoundary(next)
                                || isTerminalReviewLine(next)
                                || next.hasPrefix("Prompt for AI Agent:")
                                || next.hasPrefix("Type: ")
                                || next.hasPrefix("Line: ")
                                || next.hasPrefix("Also applies to: ")
                        }
                    )
                    let cleanedFixLines = trimTrailingNarrativeAfterDiff(in: parsed.contentLines)
                    proposedFixLines = parseDiffLines(from: cleanedFixLines)
                    index = parsed.nextIndex
                    continue
                }

                if trimmed.hasPrefix("Prompt for AI Agent:") {
                    let parsed = parseBlockContent(
                        lines: lines,
                        startIndex: index,
                        header: "Prompt for AI Agent:",
                        stopWhen: { next in
                            isFindingBoundary(next)
                                || isTerminalReviewLine(next)
                                || next.hasPrefix("Type: ")
                                || next.hasPrefix("Line: ")
                                || next.hasPrefix("Also applies to: ")
                                || isProposedFixHeader(next)
                        }
                    )
                    let prompt = parsed.contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    aiPrompt = prompt.isEmpty ? nil : prompt
                    index = parsed.nextIndex
                    continue
                }

                index += 1
            }

            let comment = commentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let severityValue = severity(fromType: type) ?? .info
            let typeLabel = type?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedType = (typeLabel?.isEmpty == false) ? typeLabel : nil
            var finalComment = comment
            var finalProposedFixLines = proposedFixLines

            // Fallback: some findings embed a code diff inside Comment: without a dedicated
            // "Suggested/Proposed/Alternative..." header. Split that inline diff out.
            if finalProposedFixLines.isEmpty,
               let inline = splitInlineProposedFixFromComment(commentLines: commentLines)
            {
                finalComment = inline.comment
                finalProposedFixLines = parseDiffLines(from: trimTrailingNarrativeAfterDiff(in: inline.proposedFixLines))
            }
            findings.append(
                ReviewFinding(
                    severity: severityValue,
                    file: file.isEmpty ? nil : file,
                    line: lineStart,
                    lineEnd: lineEnd,
                    typeRaw: normalizedType,
                    typeDisplay: normalizedType ?? severityValue.displayName,
                    appliesTo: appliesTo,
                    commentText: finalComment.isEmpty ? (normalizedType ?? "Review finding") : finalComment,
                    proposedFixEmoji: proposedFixEmoji,
                    proposedFixTitle: proposedFixTitle,
                    proposedFix: finalProposedFixLines.isEmpty ? nil : ReviewDiffBlock(lines: finalProposedFixLines),
                    aiPrompt: aiPrompt
                )
            )
        }

        return findings
    }

    private static func parseLineRange(from line: String) -> (start: Int?, end: Int?)? {
        let pattern = #"^Line:\s*(\d+)(?:\s*(?:to|-)\s*(\d+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsrange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: nsrange) else { return nil }

        guard let startRange = Range(match.range(at: 1), in: line) else { return nil }
        let start = Int(String(line[startRange]))

        var end: Int?
        if match.range(at: 2).location != NSNotFound,
           let endRange = Range(match.range(at: 2), in: line) {
            end = Int(String(line[endRange]))
        }

        return (start, end)
    }

    private static func severity(fromType type: String?) -> ReviewSeverity? {
        guard let type else { return nil }
        let lowered = type.lowercased()
        if lowered.contains("error") { return .error }
        if lowered.contains("warning") || lowered.contains("potential") { return .warning }
        return .info
    }

    static func parsePhases(from text: String) -> [ReviewPhase] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var phases: [ReviewPhase] = []
        var seen = Set<ReviewPhase>()

        for line in lines {
            let trimmed = sanitizeLineForParsing(line)
            guard let phase = phase(from: trimmed) else { continue }
            if !seen.contains(phase) {
                phases.append(phase)
                seen.insert(phase)
            }
        }

        return phases
    }

    static func parseCompletionSummary(from text: String) -> ReviewCompletionSummary? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for raw in lines.reversed() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("Review completed:") else { continue }

            let suffix = String(line.dropFirst("Review completed:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = suffix.lowercased()
            if lowered.hasPrefix("no findings") {
                return ReviewCompletionSummary(findingCount: 0, hasNoFindings: true, rawLine: line)
            }

            if let count = parseLeadingInteger(from: suffix) {
                return ReviewCompletionSummary(findingCount: count, hasNoFindings: count == 0, rawLine: line)
            }

            return ReviewCompletionSummary(findingCount: nil, hasNoFindings: false, rawLine: line)
        }

        return nil
    }

    private static func phase(from line: String) -> ReviewPhase? {
        if line.hasPrefix("Starting CodeRabbit review") { return .starting }
        if line == "Connecting to review service" { return .connecting }
        if line == "Setting up" { return .settingUp }
        if line == "Analyzing" { return .analyzing }
        if line == "Reviewing" { return .reviewing }
        if line.hasPrefix("Review completed:") { return .complete }
        if line.hasPrefix("Failed to start review:") { return .complete }
        return nil
    }

    static func parseRunFailureMessage(from text: String) -> String? {
        parseRunErrorInfo(from: text)?.message
    }

    static func parseRunErrorInfo(from text: String) -> ReviewRunErrorInfo? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Prioritize explicit rate-limit errors over generic follow-up lines like
        // "Failed to start review" or "[error] stopping cli".
        for raw in lines.reversed() {
            let line = sanitizeLineForParsing(raw)
            guard !line.isEmpty else { continue }
            guard isExplicitRateLimitErrorLine(line) else { continue }

            let occurredAt = parseTimestamp(from: line)
            var cleaned = line
            if let closingBracket = cleaned.firstIndex(of: "]"), cleaned.hasPrefix("[") {
                cleaned = String(cleaned[cleaned.index(after: closingBracket)...]).trimmingCharacters(in: .whitespaces)
            }
            cleaned = cleaned.replacingOccurrences(of: "❌ ERROR: Error:", with: "", options: [.caseInsensitive])
            cleaned = cleaned.replacingOccurrences(of: "ERROR: Error:", with: "", options: [.caseInsensitive])
            cleaned = cleaned.replacingOccurrences(of: "Error:", with: "", options: [.caseInsensitive])
            let message = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            let retryAfter = parseRetryAfterText(from: message)
            return ReviewRunErrorInfo(
                message: message,
                isRateLimit: true,
                retryAfter: retryAfter,
                retryAfterSeconds: retryAfter.flatMap(parseRetryAfterSeconds(from:)),
                occurredAt: occurredAt,
                rawLine: line
            )
        }

        for raw in lines.reversed() {
            let line = sanitizeLineForParsing(raw)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("Failed to start review:") {
                let message = String(line.dropFirst("Failed to start review:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return ReviewRunErrorInfo(message: message, isRateLimit: false, retryAfter: nil, retryAfterSeconds: nil, occurredAt: parseTimestamp(from: line), rawLine: line)
            }

            if line.lowercased().hasPrefix("[error]") {
                return ReviewRunErrorInfo(message: line, isRateLimit: false, retryAfter: nil, retryAfterSeconds: nil, occurredAt: parseTimestamp(from: line), rawLine: line)
            }
        }

        return nil
    }

    private static func isExplicitRateLimitErrorLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        guard lowered.contains("rate limit exceeded") else { return false }

        // Match only runtime error surfaces, not finding/comment/prompt text.
        return lowered.hasPrefix("[error]")
            || lowered.hasPrefix("error:")
            || lowered.hasPrefix("failed to start review:")
            || lowered.hasPrefix("❌ error:")
            || lowered.hasPrefix("❌")
            || isTimestampedErrorLine(lowered)
    }

    private static func isTimestampedErrorLine(_ loweredLine: String) -> Bool {
        guard loweredLine.hasPrefix("[") else { return false }
        guard let closeBracket = loweredLine.firstIndex(of: "]") else { return false }
        let suffix = loweredLine[loweredLine.index(after: closeBracket)...].trimmingCharacters(in: .whitespaces)
        return suffix.hasPrefix("❌ error:") || suffix.hasPrefix("error:")
    }

    private static func parseBlockContent(
        lines: [String],
        startIndex: Int,
        header: String?,
        stopWhen: (String) -> Bool
    ) -> (contentLines: [String], nextIndex: Int) {
        var index = startIndex
        var content: [String] = []

        if let header {
            let currentTrimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let remainder = String(currentTrimmed.dropFirst(header.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainder.isEmpty {
                content.append(remainder)
            }
            index += 1
        } else {
            index += 1
        }

        while index < lines.count {
            let raw = lines[index]
            let trimmed = sanitizeLineForParsing(raw)
            if stopWhen(trimmed) {
                break
            }
            content.append(raw)
            index += 1
        }

        let normalized = trimOuterEmptyLines(content)
        return (normalized, index)
    }

    private static func parseDiffLines(from lines: [String]) -> [ReviewDiffLine] {
        var parsed: [ReviewDiffLine] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let leadingTrimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                parsed.append(ReviewDiffLine(kind: .context, text: ""))
                continue
            }

            let kind: ReviewDiffLineKind
            if leadingTrimmed.hasPrefix("+") {
                kind = .added
            } else if leadingTrimmed.hasPrefix("-") {
                kind = .removed
            } else if leadingTrimmed.hasPrefix("@@")
                || leadingTrimmed.hasPrefix("diff ")
                || leadingTrimmed.hasPrefix("index ")
                || leadingTrimmed.hasPrefix("---")
                || leadingTrimmed.hasPrefix("+++")
            {
                kind = .meta
            } else {
                kind = .context
            }

            parsed.append(ReviewDiffLine(kind: kind, text: line))
        }

        return parsed
    }

    private static func trimTrailingNarrativeAfterDiff(in lines: [String]) -> [String] {
        guard lines.contains(where: isDiffMarkerLine) else {
            return lines
        }

        var trimmed = lines
        while let last = trimmed.last {
            let line = last.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                trimmed.removeLast()
                continue
            }
            if isLikelyCodeOrDiffLine(last) {
                break
            }
            trimmed.removeLast()
        }
        return trimOuterEmptyLines(trimmed)
    }

    private static func splitInlineProposedFixFromComment(commentLines: [String]) -> (comment: String, proposedFixLines: [String])? {
        if let firstDiffIndex = commentLines.firstIndex(where: isDiffMarkerLine) {
            var start = firstDiffIndex

            // Include preceding indented/context code lines that belong to the snippet.
            while start > 0 {
                let previous = commentLines[start - 1]
                let trimmed = previous.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    start -= 1
                    continue
                }
                if isLikelyCodeOrDiffLine(previous) {
                    start -= 1
                    continue
                }
                break
            }

            let commentPart = trimOuterEmptyLines(Array(commentLines[..<start])).joined(separator: "\n")
            let fixPart = trimOuterEmptyLines(Array(commentLines[start...]))
            guard !fixPart.isEmpty else { return nil }
            return (comment: commentPart, proposedFixLines: fixPart)
        }

        // Fallback: detect inline example code snippets without diff markers.
        guard let exampleIntroIndex = commentLines.firstIndex(where: isExampleCodeIntroLine) else { return nil }
        let candidateFix = Array(commentLines[exampleIntroIndex...])
        let cleanedFix = trimTrailingNarrativeAfterCodeSnippet(in: candidateFix)
        guard cleanedFix.contains(where: isLikelyStandaloneCodeLine) else { return nil }

        let commentPart = trimOuterEmptyLines(Array(commentLines[..<exampleIntroIndex])).joined(separator: "\n")
        return (comment: commentPart, proposedFixLines: cleanedFix)
    }

    private static func isDiffMarkerLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("+")
            || trimmed.hasPrefix("-")
            || trimmed.hasPrefix("@@")
            || trimmed.hasPrefix("diff ")
            || trimmed.hasPrefix("index ")
            || trimmed.hasPrefix("---")
            || trimmed.hasPrefix("+++")
    }

    private static func isLikelyCodeOrDiffLine(_ line: String) -> Bool {
        if isDiffMarkerLine(line) {
            return true
        }
        // Preserve indented/context code lines in mixed diff-style blocks.
        return line.hasPrefix(" ") || line.hasPrefix("\t")
    }

    private static func isExampleCodeIntroLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("// example:")
            || trimmed.hasPrefix("example:")
    }

    private static func isLikelyStandaloneCodeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if isDiffMarkerLine(trimmed) || isExampleCodeIntroLine(trimmed) {
            return true
        }

        let indicators = [
            "let ", "var ", "if ", "guard ", "for ", "while ", "switch ", "case ",
            "func ", "enum ", "struct ", "class ", "@", "return ", "throw ", "try ",
            "XCT", "sut.", "self.", "await ", "{", "}"
        ]
        return indicators.contains(where: { trimmed.hasPrefix($0) }) || trimmed.contains("(") || trimmed.contains(")")
    }

    private static func trimTrailingNarrativeAfterCodeSnippet(in lines: [String]) -> [String] {
        var trimmed = lines
        while let last = trimmed.last {
            let line = last.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                trimmed.removeLast()
                continue
            }
            if isLikelyStandaloneCodeLine(last) {
                break
            }
            trimmed.removeLast()
        }
        return trimOuterEmptyLines(trimmed)
    }

    private static func isFindingBoundary(_ line: String) -> Bool {
        line.hasPrefix("====") || line.hasPrefix("File: ")
    }

    private static func isTerminalReviewLine(_ line: String) -> Bool {
        line.hasPrefix("Review completed:")
            || line.hasPrefix("Failed to start review:")
            || line.lowercased().hasPrefix("[error]")
    }

    private static func isProposedFixHeader(_ line: String) -> Bool {
        parseProposedFixHeaderComponents(from: line) != nil
    }

    private static func proposedFixTitleFromHeader(_ line: String) -> String? {
        parseProposedFixHeaderComponents(from: line)?.title
    }

    private static func leadingEmoji(from line: String) -> String? {
        parseProposedFixHeaderComponents(from: line)?.emoji
    }

    private static func parseProposedFixHeaderComponents(from line: String) -> (emoji: String?, title: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let emoji: String?
        let titleCandidate: String
        if startsWithEmoji(trimmed), let first = trimmed.first {
            emoji = String(first)
            titleCandidate = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            emoji = nil
            titleCandidate = trimmed
        }

        guard !titleCandidate.isEmpty else { return nil }
        guard isRecognizedProposedFixTitle(titleCandidate) else { return nil }
        return (emoji: emoji, title: titleCandidate)
    }

    private static func isRecognizedProposedFixTitle(_ title: String) -> Bool {
        let pattern = #"^(?:(?:proposed|suggested|recommended)\s+(?:fix|approach|improvement|naming\s+convention)\b.*|alternative\b.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        return regex.firstMatch(in: title, options: [], range: range) != nil
    }

    private static func startsWithEmoji(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstScalar = trimmed.unicodeScalars.first else { return false }
        return firstScalar.properties.isEmojiPresentation || firstScalar.properties.isEmoji
    }

    private static func parseLeadingInteger(from text: String) -> Int? {
        let digits = text.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    private static func parseRetryAfterText(from message: String) -> String? {
        let marker = "please try after "
        guard let range = message.range(of: marker, options: [.caseInsensitive]) else { return nil }
        let retry = String(message[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return retry.isEmpty ? nil : retry
    }

    nonisolated private static func parseRetryAfterSeconds(from text: String) -> TimeInterval? {
        let lowered = text.lowercased()
        let pattern = #"(\d+)\s*(minute|minutes|second|seconds)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsrange = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
        let matches = regex.matches(in: lowered, options: [], range: nsrange)
        guard !matches.isEmpty else { return nil }

        var totalSeconds: Int = 0
        for match in matches {
            guard
                let valueRange = Range(match.range(at: 1), in: lowered),
                let unitRange = Range(match.range(at: 2), in: lowered),
                let value = Int(lowered[valueRange])
            else { continue }

            let unit = lowered[unitRange]
            if unit.hasPrefix("minute") {
                totalSeconds += value * 60
            } else {
                totalSeconds += value
            }
        }

        return totalSeconds > 0 ? TimeInterval(totalSeconds) : nil
    }

    private static func trimOuterEmptyLines(_ lines: [String]) -> [String] {
        var lower = 0
        var upper = lines.count - 1

        while lower < lines.count && lines[lower].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lower += 1
        }
        while upper >= lower && lines[upper].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            upper -= 1
        }

        guard lower <= upper else { return [] }
        return Array(lines[lower...upper])
    }

    private static func parseTimestamp(from line: String) -> Date? {
        guard let start = line.firstIndex(of: "["),
              let end = line[line.index(after: start)...].firstIndex(of: "]"),
              start < end else { return nil }
        let candidate = String(line[line.index(after: start)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: candidate) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: candidate)
    }

    private static func sanitizeLineForParsing(_ line: String) -> String {
        stripANSIEscapeCodes(from: line).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripANSIEscapeCodes(from line: String) -> String {
        let pattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return line }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.stringByReplacingMatches(in: line, options: [], range: range, withTemplate: "")
    }
}
