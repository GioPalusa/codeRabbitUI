//
//  ContentView+Logic.swift
//  CodeRabbit
//

import AppKit
import SwiftUI
import UserNotifications

extension ContentView {
    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            selectedProjectFolderPath = url.path
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmark, forKey: projectFolderBookmarkKey)
            }
        }
    }

    func loadRecentProjectFolders() {
        guard let data = recentProjectFoldersJSON.data(using: .utf8) else {
            recentProjectFolders = []
            return
        }
        let decodedFolders = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        recentProjectFolders = decodedFolders.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func rememberProjectFolder(_ folderPath: String) {
        let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        recentProjectFolders.removeAll { $0 == trimmed }
        recentProjectFolders.insert(trimmed, at: 0)
        if recentProjectFolders.count > 15 {
            recentProjectFolders = Array(recentProjectFolders.prefix(15))
        }

        guard let data = try? JSONEncoder().encode(recentProjectFolders),
              let encoded = String(data: data, encoding: .utf8)
        else { return }
        recentProjectFoldersJSON = encoded
    }

    func folderMenuLabel(for folderPath: String) -> String {
        let folderName = URL(fileURLWithPath: folderPath).lastPathComponent
        if folderName.isEmpty {
            return folderPath
        }
        return "\(folderName) (\(folderPath))"
    }

    var availableProjectFolders: [String] {
        let trimmedSelection = selectedProjectFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSelection.isEmpty || recentProjectFolders.contains(trimmedSelection) {
            return recentProjectFolders
        }
        return [trimmedSelection] + recentProjectFolders
    }

    func normalizedReviewType(_ value: String) -> String {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lowered {
        case "committed", "uncommitted":
            return lowered
        default:
            return "all"
        }
    }

    var parsedReviewConfigFiles: [String] {
        guard let data = reviewConfigFilesJSON.data(using: .utf8) else {
            return []
        }
        let decodedFiles = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        return decodedFiles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var effectiveCommandPreview: String {
        let command = selectedReviewCommand
        var parts: [String] = [command]
        let typeValue = normalizedReviewType(reviewType)
        if !commandContainsFlag(command, long: "--type", short: "-t") {
            parts.append("--type \(typeValue)")
        }
        let configFiles = parsedReviewConfigFiles
        if !configFiles.isEmpty, !commandContainsFlag(command, long: "--config", short: "-c") {
            parts.append("--config \(configFiles.joined(separator: " "))")
        }
        switch normalizedComparisonBaseMode(comparisonBaseMode) {
        case .automatic:
            break
        case .baseBranch:
            let branch = comparisonBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            if !branch.isEmpty, !commandContainsFlag(command, long: "--base") {
                parts.append("--base \(branch)")
            }
        case .baseCommit:
            let commit = comparisonBaseCommit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !commit.isEmpty, !commandContainsFlag(command, long: "--base-commit") {
                parts.append("--base-commit \(commit)")
            }
        }
        return parts.joined(separator: " ")
    }

    var selectedReviewCommand: String {
        switch normalizedReviewOutputMode(reviewOutputMode) {
        case .full:
            return "review --plain"
        case .promptOnly:
            return "review --prompt-only"
        }
    }

    func normalizedReviewOutputMode(_ value: String) -> ReviewOutputMode {
        ReviewOutputMode(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .full
    }

    var isDarkMode: Bool {
        colorScheme == .dark
    }

    var triggerHeroBackgroundGradient: LinearGradient {
        let colors: [Color]
        if isDarkMode {
            colors = [
                Color(red: 0.20, green: 0.10, blue: 0.04),
                Color(red: 0.36, green: 0.17, blue: 0.06),
                Color(red: 0.16, green: 0.07, blue: 0.03),
            ]
        } else {
            colors = [
                Color(red: 0.99, green: 0.97, blue: 0.94),
                Color(red: 0.96, green: 0.91, blue: 0.84),
                Color(red: 0.95, green: 0.93, blue: 0.89),
            ]
        }

        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var triggerHeroOrbPrimaryColor: Color {
        isDarkMode ? Color.white.opacity(0.08) : Color.white.opacity(0.6)
    }

    var triggerHeroOrbAccentColor: Color {
        isDarkMode ? Color.orange.opacity(0.22) : Color.orange.opacity(0.18)
    }

    var triggerHeroTitleColor: Color {
        isDarkMode ? .white : Color(red: 0.16, green: 0.11, blue: 0.08)
    }

    var triggerHeroSubtitleColor: Color {
        isDarkMode ? Color.white.opacity(0.85) : Color.black.opacity(0.72)
    }

    var triggerSettingLabelColor: Color {
        isDarkMode ? Color.white.opacity(0.72) : Color.black.opacity(0.62)
    }

    var triggerCommandPreviewColor: Color {
        isDarkMode ? Color.white.opacity(0.95) : Color.black.opacity(0.86)
    }

    var triggerSettingsPanelBorderColor: Color {
        isDarkMode ? Color.white.opacity(0.24) : Color.black.opacity(0.14)
    }

    var triggerHeroInputBorderColor: Color {
        isDarkMode ? Color.white.opacity(0.18) : Color.black.opacity(0.10)
    }

    var triggerActionTintColor: Color {
        isDarkMode ? Color(red: 0.92, green: 0.54, blue: 0.14) : Color(red: 0.70, green: 0.33, blue: 0.05)
    }

    var latestCLIUpdateCommand: String? {
        if let command = ReviewParser.parseCLIUpdateCommand(from: runner.rawOutput) {
            return command
        }

        if let mostRecentHistoryOutput = historyStore.items.first?.rawOutput {
            return ReviewParser.parseCLIUpdateCommand(from: mostRecentHistoryOutput)
        }

        return nil
    }

    func cliUpdatePromptCard(command: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(triggerActionTintColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("CodeRabbit CLI update available")
                    .font(.headline)
                    .foregroundStyle(triggerHeroTitleColor)
                Text("Run `\(command)` before your next review.")
                    .font(.subheadline)
                    .foregroundStyle(triggerHeroSubtitleColor)
            }

            Spacer(minLength: 0)

            Button("Copy Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
            .buttonStyle(.borderedProminent)
            .tint(triggerActionTintColor)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 14, borderColor: triggerActionTintColor.opacity(0.7), lineWidth: 1.2)
    }

    func requestNotificationAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        }
    }

    func sendReviewCompletionNotification() {
        let content = UNMutableNotificationContent()
        let trimmedFolderPath = runner.selectedFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = URL(fileURLWithPath: trimmedFolderPath).lastPathComponent
        let hasFolderName = folderName.isEmpty == false

        switch runner.status {
        case let .completed(code):
            if code == 0 {
                let count = runner.findings.count
                content.title = "Review completed"
                if count == 0 {
                    content.body = hasFolderName
                        ? "No findings for \(folderName)."
                        : "No findings detected."
                } else {
                    content.body = hasFolderName
                        ? "\(count) finding\(count == 1 ? "" : "s") in \(folderName)."
                        : "\(count) finding\(count == 1 ? "" : "s") detected."
                }
            } else {
                content.title = "Review completed with issues"
                content.body = hasFolderName
                    ? "\(statusText) (\(folderName))"
                    : statusText
            }
        case .failed:
            content.title = "Review failed"
            content.body = hasFolderName
                ? "\(statusText) (\(folderName))"
                : statusText
        case .idle, .running:
            return
        }

        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "review-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func normalizedComparisonBaseMode(_ value: String) -> ComparisonBaseMode {
        ComparisonBaseMode(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .automatic
    }

    func requestDockBounceForCompletedReview() {
        guard NSApp.isActive == false else { return }
        NSApp.requestUserAttention(.criticalRequest)
    }

    func applyComparisonBaseToRunner() {
        switch normalizedComparisonBaseMode(comparisonBaseMode) {
        case .automatic:
            runner.baseBranch = ""
            runner.baseCommit = ""
        case .baseBranch:
            runner.baseBranch = comparisonBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            runner.baseCommit = ""
        case .baseCommit:
            runner.baseBranch = ""
            runner.baseCommit = comparisonBaseCommit.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func selectedBaseReferenceForSummary() -> String? {
        switch normalizedComparisonBaseMode(comparisonBaseMode) {
        case .automatic:
            return nil
        case .baseBranch:
            let value = comparisonBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        case .baseCommit:
            let value = comparisonBaseCommit.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    func refreshGitChangeSummary(for folderPath: String) {
        let trimmedFolderPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFolderPath.isEmpty else {
            gitChangeSummary = nil
            isLoadingGitChangeSummary = false
            return
        }

        gitChangeSummaryRequestID += 1
        let requestID = gitChangeSummaryRequestID
        isLoadingGitChangeSummary = true
        let baseRef = selectedBaseReferenceForSummary()

        Task {
            let summary = await runner.loadGitChangeSummary(in: trimmedFolderPath, baseRef: baseRef)
            await MainActor.run {
                guard requestID == gitChangeSummaryRequestID else { return }
                isLoadingGitChangeSummary = false
                gitChangeSummary = summary
            }
        }
    }

    func refreshGitBranches(for folderPath: String) {
        let trimmedFolderPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFolderPath.isEmpty else {
            gitBranches = []
            gitBranchLookupFailed = false
            isLoadingGitBranches = false
            return
        }

        gitBranchesRequestID += 1
        let requestID = gitBranchesRequestID
        isLoadingGitBranches = true
        gitBranchLookupFailed = false

        Task {
            let fetchedBranches = await runner.listGitLocalBranches(in: trimmedFolderPath)
            await MainActor.run {
                guard requestID == gitBranchesRequestID else { return }
                isLoadingGitBranches = false
                if let fetchedBranches, !fetchedBranches.isEmpty {
                    gitBranches = fetchedBranches
                    gitBranchLookupFailed = false
                    if normalizedComparisonBaseMode(comparisonBaseMode) == .baseBranch,
                       comparisonBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        comparisonBaseBranch = fetchedBranches[0]
                    }
                } else {
                    gitBranches = []
                    gitBranchLookupFailed = true
                }
            }
        }
    }

    @ViewBuilder
    func comparisonBaseControls(isTriggerLayout: Bool) -> some View {
        let modeBinding = Binding(
            get: { normalizedComparisonBaseMode(comparisonBaseMode) },
            set: { comparisonBaseMode = $0.rawValue }
        )

        HStack {
            if isTriggerLayout {
                Picker("Comparison base", selection: modeBinding) {
                    Text("Default").tag(ComparisonBaseMode.automatic)
                    Text("Branch").tag(ComparisonBaseMode.baseBranch)
                    Text("Commit").tag(ComparisonBaseMode.baseCommit)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            } else {
                Picker("Comparison base", selection: modeBinding) {
                    Text("Default").tag(ComparisonBaseMode.automatic)
                    Text("Branch").tag(ComparisonBaseMode.baseBranch)
                    Text("Commit").tag(ComparisonBaseMode.baseCommit)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            switch normalizedComparisonBaseMode(comparisonBaseMode) {
            case .automatic:
                EmptyView()
            case .baseBranch:
                if isLoadingGitBranches {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading Git branches...")
                            .font(.caption)
                            .foregroundStyle(isTriggerLayout ? Color.white.opacity(0.85) : .secondary)
                    }
                } else if !gitBranches.isEmpty {
                    Picker("Base branch", selection: $comparisonBaseBranch) {
                        ForEach(gitBranches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .padding(.leading)
                } else {
                    TextField("main", text: $comparisonBaseBranch)
                        .textFieldStyle(.roundedBorder)
                    if gitBranchLookupFailed {
                        Text("Branch lookup failed. Enter a branch name manually.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            case .baseCommit:
                TextField("Commit SHA", text: $comparisonBaseCommit)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    func commandContainsFlag(_ command: String, long: String, short: String? = nil) -> Bool {
        let args = command.split(separator: " ").map(String.init)
        return args.contains(where: {
            $0 == long
                || (short != nil && $0 == short)
                || $0.hasPrefix("\(long)=")
        })
    }

    func locationText(for finding: ReviewFinding) -> String? {
        guard let file = finding.file, !file.isEmpty else { return nil }
        guard let line = finding.line else { return file }
        if let lineEnd = finding.lineEnd, lineEnd != line {
            return "\(file):\(line)-\(lineEnd)"
        }
        return "\(file):\(line)"
    }

    func historyTitle(for item: ReviewHistoryItem) -> String {
        let folderName = URL(fileURLWithPath: item.folderPath).lastPathComponent
        if folderName.isEmpty { return "Review" }
        return folderName
    }

    func historyListSummary(for item: ReviewHistoryItem) -> (text: String, color: Color) {
        if runner.currentRunID == item.id {
            return ("Running", .accentColor)
        }

        let loweredStatus = historyStatusLabel(for: item).lowercased()
        if loweredStatus.contains("failed") || loweredStatus.contains("error") || loweredStatus.contains("rate limit") {
            return ("Failed", .red)
        }

        let findings = resolvedFindings(for: item)
        let completion = ReviewParser.parseCompletionSummary(from: item.rawOutput)
        let count = completion?.findingCount ?? findings.count
        if count == 0 {
            return ("No findings", .green)
        }

        let hasPotentialIssue = findings.contains { finding in
            finding.typeRaw?.lowercased().contains("potential_issue") == true
        }
        if hasPotentialIssue {
            return ("\(count) finding\(count == 1 ? "" : "s")", .orange)
        }

        let hasError = findings.contains { $0.severity == .error }
        if hasError {
            return ("\(count) finding\(count == 1 ? "" : "s")", .red)
        }

        return ("\(count) finding\(count == 1 ? "" : "s")", .accentColor)
    }

    var displayedHistoryItems: [ReviewHistoryItem] {
        if let inProgressHistoryItem {
            return [inProgressHistoryItem] + historyStore.items.filter { $0.id != inProgressHistoryItem.id }
        }
        return historyStore.items
    }

    var inProgressHistoryItem: ReviewHistoryItem? {
        guard let runID = runner.currentRunID else { return nil }
        return ReviewHistoryItem(
            id: runID,
            createdAt: runner.currentRunStartedAt ?? Date(),
            command: runner.command,
            folderPath: runner.selectedFolderPath,
            rawOutput: runner.rawOutput,
            findings: runner.findings,
            phases: runner.phases,
            statusLabel: statusText
        )
    }

    func historyItem(for id: UUID) -> ReviewHistoryItem? {
        if inProgressHistoryItem?.id == id {
            return inProgressHistoryItem
        }
        return historyStore.items.first(where: { $0.id == id })
    }

    var groupedHistoryItems: [HistoryFolderGroup] {
        var grouped: [String: [ReviewHistoryItem]] = [:]
        var order: [String] = []

        for item in displayedHistoryItems {
            let folderPath = normalizedFolderPath(item.folderPath)
            if grouped[folderPath] == nil {
                grouped[folderPath] = []
                order.append(folderPath)
            }
            grouped[folderPath, default: []].append(item)
        }

        return order.map { folderPath in
            HistoryFolderGroup(
                folderPath: folderPath,
                items: grouped[folderPath] ?? []
            )
        }
    }

    func isHistoryGroupExpandedBinding(for folderPath: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedHistoryFolders.contains(folderPath) },
            set: { isExpanded in
                if isExpanded {
                    collapsedHistoryFolders.remove(folderPath)
                } else {
                    collapsedHistoryFolders.insert(folderPath)
                }
            }
        )
    }

    func historyFolderName(for folderPath: String) -> String {
        let folderName = URL(fileURLWithPath: folderPath).lastPathComponent
        return folderName.isEmpty ? "Unknown Folder" : folderName
    }

    func normalizedFolderPath(_ folderPath: String) -> String {
        let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "/" : trimmed
    }

    func normalizeTypeLabel(_ raw: String) -> String {
        let withSpaces = raw.replacingOccurrences(of: "_", with: " ")
        guard let first = withSpaces.first else { return raw }
        return first.uppercased() + withSpaces.dropFirst()
    }

    func promptKey(for finding: ReviewFinding) -> String {
        [
            finding.file ?? "",
            String(finding.line ?? 0),
            String(finding.lineEnd ?? 0),
            finding.typeRaw ?? finding.typeDisplay,
            finding.aiPrompt ?? "",
        ].joined(separator: "|")
    }

    func combinedPromptKey(for prompt: String) -> String {
        "combined|\(prompt.count)|\(prompt.hashValue)"
    }

    func resolvedFindings(for item: ReviewHistoryItem) -> [ReviewFinding] {
        let reparsed = ReviewParser.parse(from: item.rawOutput)
        if ReviewParser.parseRunErrorInfo(from: item.rawOutput) != nil {
            return []
        }
        return reparsed.isEmpty ? item.findings : reparsed
    }

    func historyStatusLabel(for item: ReviewHistoryItem) -> String {
        if let errorInfo = ReviewParser.parseRunErrorInfo(from: item.rawOutput) {
            if errorInfo.isRateLimit, let retryAfter = errorInfo.retryAfter, !retryAfter.isEmpty {
                return "Rate limit reached. Try again in \(retryAfter)."
            }
            return "Failed: \(errorInfo.message)"
        }

        if let completion = ReviewParser.parseCompletionSummary(from: item.rawOutput) {
            if completion.hasNoFindings {
                return "No findings. Excellent work!"
            }
            if let count = completion.findingCount {
                return "Review completed: \(count) finding\(count == 1 ? "" : "s")"
            }
            return "Completed successfully"
        }

        return item.statusLabel
    }

    func historySubtitle(for item: ReviewHistoryItem) -> String {
        let dateText = Self.historyDateFormatter.string(from: item.createdAt)
        return "\(dateText) • \(historyStatusLabel(for: item))"
    }

    static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static let cooldownDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    func countdownLabel(until date: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.countdownString(until: date, relativeTo: context.date))
                .monospacedDigit()
        }
    }

    static func countdownString(until date: Date, relativeTo now: Date) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var loadingRabbitASCII: String {
        #"""

        		/|      __
        	   / |   ,-~ /
        	  Y :|  //  /
        	  | jj /( .^
        	  >-"~"-v"
        	 /       Y
        	jo  o    |
           ( ~T~     j
        	>._-' _./
           /   "~"  |
          Y     _,  |
         /| ;-"~ _  l
        / l/ ,-"~    \
        \//\/      .- \
         Y        /    Y
         l       I     !
         ]\      _\    /"\
        (" ~----( ~   Y.  )
        ~~~~~~~~~~~~~~~~~~~~~~~~~
        """#
    }

    func findingsEmptyStateText(hasNoFindingsResult: Bool, hasAnyOutput: Bool) -> String {
        if hasNoFindingsResult {
            return "No findings. Excellent review!"
        }
        if !hasAnyOutput {
            return "Run a review to see findings."
        }
        return "No findings parsed for this run."
    }

    func historyNextAllowedRunAt(for errorInfo: ReviewRunErrorInfo) -> Date? {
        guard errorInfo.isRateLimit, let retryAfterSeconds = errorInfo.retryAfterSeconds else { return nil }
        return (errorInfo.occurredAt ?? Date()).addingTimeInterval(retryAfterSeconds)
    }

    func historyHasFailed(_ item: ReviewHistoryItem) -> Bool {
        let loweredStatus = historyStatusLabel(for: item).lowercased()
        return loweredStatus.contains("failed")
            || loweredStatus.contains("error")
            || loweredStatus.contains("rate limit")
    }
}
