//
//  ContentView+UI.swift
//  CodeRabbit
//

import AppKit
import SwiftUI

extension ContentView {
    var sidebarView: some View {
        List {
            ForEach(sidebarSectionOrder) { section in
                switch section {
                case .newReview:
                    if sidebarShowNewReview {
                        Section("Review") {
                            Button {
                                selection = .current
                                forceShowNewReviewTriggerPage = true
                                if !isRunning {
                                    runner.prepareForNewReview()
                                }
                                selectedLiveTab = 0
                                expandedPromptKeys.removeAll()
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "square.and.pencil")
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("New Review")
                                            .font(.subheadline.weight(.semibold))
                                        Text("Start a clean review run")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .listRowBackground(selection == .current ? Color.accentColor.opacity(0.2) : Color.clear)
                        }
                    }
                case .history:
                    if sidebarShowHistory {
                        sidebarHistorySection
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    var sidebarHistorySection: some View {
        Section("History") {
            ForEach(groupedHistoryItems) { group in
                DisclosureGroup(
                    isExpanded: isHistoryGroupExpandedBinding(for: group.folderPath),
                    content: {
                        ForEach(group.items) { item in
                            let rowSelection: ReviewSelection = .history(item.id)
                            let summary = historyListSummary(for: item)
                            Button {
                                selection = rowSelection
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(summary.color)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 4)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(historyTitle(for: item))
                                            .lineLimit(1)
                                        Text("\(summary.text) • \(Self.historyDateFormatter.string(from: item.createdAt))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selection == rowSelection ? Color.accentColor.opacity(0.2) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    },
                    label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(historyFolderName(for: group.folderPath))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(group.items.count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                )
            }
        }
    }

    var sidebarPrimarySection: SidebarPrimarySection {
        SidebarPrimarySection(rawValue: sidebarPrimarySectionRaw) ?? .newReview
    }

    var sidebarSectionOrder: [SidebarPrimarySection] {
        switch sidebarPrimarySection {
        case .newReview:
            return [.newReview, .history]
        case .history:
            return [.history, .newReview]
        }
    }

    @ViewBuilder
    var detailView: some View {
        switch selection {
        case let .history(id):
            if let item = historyItem(for: id) {
                historyDetailView(item)
            } else {
                missingHistoryView
            }
        default:
            liveDetailView
        }
    }

    var liveDetailView: some View {
        Group {
            if showsNewReviewTriggerPage {
                newReviewTriggerView
                    .backgroundExtensionEffect()
            } else {
                VStack(spacing: 12) {
                    headerSection(title: "New Review", subtitle: statusText, subtitleColor: statusColor)
                    controlsSection
                    reviewStatusCard(
                        phases: runner.phases,
                        findings: runner.findings,
                        rawOutput: runner.rawOutput,
                        isRunning: isRunning,
                        hasFailed: isLiveRunFailed
                    )
                    if let runErrorInfo = runner.runErrorInfo {
                        errorCard(errorInfo: runErrorInfo, nextAllowedRunAt: runner.nextAllowedRunAt)
                    } else if case let .failed(message) = runner.status {
                        errorFallbackCard(message: message)
                    }
                    Divider()
                    resultsSection(
                        command: runner.command,
                        findings: runner.findings,
                        rawOutput: runner.rawOutput,
                        selectedTab: $selectedLiveTab,
                        showsLoadingPlaceholder: isRunning
                    )
                }
                .padding(16)
                .frame(minWidth: 760, minHeight: 680)
            }
        }
    }

    var showsNewReviewTriggerPage: Bool {
        if forceShowNewReviewTriggerPage { return true }
        if isRunning { return false }
        if !runner.phases.isEmpty { return false }
        if !runner.rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if !runner.findings.isEmpty { return false }
        if case .failed = runner.status { return false }
        return true
    }

    var newReviewTriggerView: some View {
        ZStack(alignment: .topTrailing) {
            triggerHeroBackgroundGradient
                .ignoresSafeArea()

            Circle()
                .fill(triggerHeroOrbPrimaryColor)
                .frame(width: 280, height: 280)
                .blur(radius: 10)
                .offset(x: -260, y: -180)

            Circle()
                .fill(triggerHeroOrbAccentColor)
                .frame(width: 220, height: 220)
                .blur(radius: 18)
                .offset(x: 250, y: 180)

            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    Image("coderabbitlogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 360)
                        .shadow(color: triggerActionTintColor.opacity(0.2), radius: 8, x: 0, y: 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Let's review your code!")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(triggerHeroTitleColor)
                        Text("Pick settings, hit start, then we switch to the full review workspace.")
                            .font(.subheadline)
                            .foregroundStyle(triggerHeroSubtitleColor)
                    }

                    changeSnapshotCard

                    if let updateCommand = latestCLIUpdateCommand {
                        cliUpdatePromptCard(command: updateCommand)
                    }

                    VStack(spacing: 10) {
                        triggerSettingRow(title: "Project Folder") {
                            Picker("Project folder", selection: $selectedProjectFolderPath) {
                                if availableProjectFolders.isEmpty {
                                    Text("No folder selected").tag("")
                                } else {
                                    ForEach(availableProjectFolders, id: \.self) { folderPath in
                                        Text(folderMenuLabel(for: folderPath)).tag(folderPath)
                                    }
                                }
                                Text("Add Workspace…").tag(addWorkspaceOptionTag)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        triggerSettingRow(title: "Review Type") {
                            Picker("Type", selection: $reviewType) {
                                Text("All").tag("all")
                                Text("Committed").tag("committed")
                                Text("Uncommitted").tag("uncommitted")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        triggerSettingRow(title: "Review Output") {
                            Picker("Output", selection: $reviewOutputMode) {
                                Text("Full detailed review").tag(ReviewOutputMode.full.rawValue)
                                Text("AI Agent response only").tag(ReviewOutputMode.promptOnly.rawValue)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        triggerSettingRow(title: "Comparison Base") {
                            comparisonBaseControls(isTriggerLayout: true)
                        }

                        triggerSettingRow(title: "Command Preview") {
                            Text(effectiveCommandPreview)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(triggerCommandPreviewColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                    .liquidGlassCard(cornerRadius: 18, borderColor: triggerSettingsPanelBorderColor)

                    HStack {
                        Spacer()
                        runActionButton
                            .tint(triggerActionTintColor)
                            .frame(maxWidth: 220)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(30)
                .frame(maxWidth: 900, alignment: .leading)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SettingsLink {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(triggerHeroTitleColor)
            }
            .padding(.top, 20)
            .padding(.trailing, 20)
            .buttonStyle(.plain)
        }
        .frame(minWidth: 760, minHeight: 680)
    }

    func triggerSettingRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(triggerSettingLabelColor)
                .frame(width: 120, alignment: .leading)

            content()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .liquidGlassField(cornerRadius: 10, borderColor: triggerHeroInputBorderColor)
        }
    }

    @ViewBuilder
    var changeSnapshotCard: some View {
        let trimmedFolderPath = selectedProjectFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderLabel = trimmedFolderPath.isEmpty ? "No workspace selected" : trimmedFolderPath

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("repo:")
                    .foregroundStyle(triggerSettingLabelColor)
                Text(folderLabel)
                    .foregroundStyle(triggerHeroTitleColor)
                    .lineLimit(1)
                if let summary = gitChangeSummary {
                    Text("·")
                        .foregroundStyle(triggerSettingLabelColor)
                    Text(summary.currentRef)
                        .foregroundStyle(triggerActionTintColor)
                    Text("→")
                        .foregroundStyle(triggerSettingLabelColor)
                    Text(summary.comparedBaseRef)
                        .foregroundStyle(triggerHeroSubtitleColor)
                }
            }
            .font(.system(.subheadline, design: .monospaced))

            if trimmedFolderPath.isEmpty {
                Text("Pick a project folder to preview change stats.")
                    .font(.caption)
                    .foregroundStyle(triggerHeroSubtitleColor)
            } else if isLoadingGitChangeSummary {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing working changes…")
                        .font(.caption)
                }
                .foregroundStyle(triggerHeroSubtitleColor)
            } else if let summary = gitChangeSummary {
                VStack(alignment: .leading, spacing: 4) {
                    Text("📁  \(summary.filesChanged) file\(summary.filesChanged == 1 ? "" : "s") changed")
                    Text("├─ \(summary.addedFiles) added / \(summary.modifiedFiles) modified\(summary.otherFiles > 0 ? " / \(summary.otherFiles) other" : "")")
                    Text("└─ +\(summary.insertions) insertions / -\(summary.deletions) deletions")
                }
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(triggerHeroTitleColor)
            } else {
                Text("No diff stats available for this repository and base selection.")
                    .font(.caption)
                    .foregroundStyle(triggerHeroSubtitleColor)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 14, borderColor: triggerSettingsPanelBorderColor)
    }

    func historyDetailView(_ item: ReviewHistoryItem) -> some View {
        let itemFindings = resolvedFindings(for: item)
        return VStack(spacing: 12) {
            headerSection(
                title: historyTitle(for: item),
                subtitle: historySubtitle(for: item),
                subtitleColor: historyStatusColor(historyStatusLabel(for: item))
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Folder: \(item.folderPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Command: \(item.command)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            reviewStatusCard(
                phases: item.phases,
                findings: itemFindings,
                rawOutput: item.rawOutput,
                isRunning: false,
                hasFailed: historyHasFailed(item)
            )
            if let runErrorInfo = ReviewParser.parseRunErrorInfo(from: item.rawOutput) {
                errorCard(errorInfo: runErrorInfo, nextAllowedRunAt: historyNextAllowedRunAt(for: runErrorInfo))
            }
            Divider()
            resultsSection(
                command: item.command,
                findings: itemFindings,
                rawOutput: item.rawOutput,
                selectedTab: $selectedHistoryTab,
                showsLoadingPlaceholder: runner.currentRunID == item.id
            )
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 680)
    }

    var missingHistoryView: some View {
        VStack {
            Text("This review is no longer available.")
                .foregroundStyle(.secondary)
            Button("Back to New Review") {
                selection = .current
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func headerSection(title: String, subtitle: String, subtitleColor: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(Color.accentColor)
                Text(subtitle)
                    .foregroundStyle(subtitleColor)
                    .font(.subheadline)
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.plain)
        }
    }

    var controlsSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 10) {
                Picker("Project folder", selection: $selectedProjectFolderPath) {
                    if availableProjectFolders.isEmpty {
                        Text("No folder selected").tag("")
                    } else {
                        ForEach(availableProjectFolders, id: \.self) { folderPath in
                            Text(folderMenuLabel(for: folderPath)).tag(folderPath)
                        }
                    }
                    Text("Add Workspace…").tag(addWorkspaceOptionTag)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Text("Type:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Type", selection: $reviewType) {
                        Text("All").tag("all")
                        Text("Committed").tag("committed")
                        Text("Uncommitted").tag("uncommitted")
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Text("Output:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Output", selection: $reviewOutputMode) {
                        Text("Full detailed review").tag(ReviewOutputMode.full.rawValue)
                        Text("AI Agent response only").tag(ReviewOutputMode.promptOnly.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Text("Compare:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    comparisonBaseControls(isTriggerLayout: false)
                }

                Text("Command: \(effectiveCommandPreview)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 10) {
                Button("Open Folder") {
                    pickFolder()
                }
                .buttonStyle(.bordered)

                runActionButton
                    .frame(maxWidth: 210)
            }
            .frame(width: 210, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func reviewStatusCard(
        phases: [ReviewPhase],
        findings _: [ReviewFinding],
        rawOutput: String,
        isRunning: Bool,
        hasFailed: Bool
    ) -> some View {
        if !shouldShowFindingsSummary(phases: phases, rawOutput: rawOutput, isRunning: isRunning, hasFailed: hasFailed) {
            progressSection(phases: phases, isRunning: isRunning, hasFailed: hasFailed)
        }
    }

    func shouldShowFindingsSummary(
        phases: [ReviewPhase],
        rawOutput: String,
        isRunning: Bool,
        hasFailed: Bool
    ) -> Bool {
        guard !isRunning, !hasFailed else { return false }
        if ReviewParser.parseCompletionSummary(from: rawOutput) != nil {
            return true
        }
        return phases.contains(.complete)
    }

    func findingsSummaryCard(findings: [ReviewFinding]) -> some View {
        let counts = findingTypeCounts(from: findings)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Findings Breakdown")
                        .font(.headline)
                    Text("Potential issues, nitpicks, and refactor suggestions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(findings.count)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Text("total")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            geometryDistributionBar(counts: counts)
                .frame(height: 14)

            HStack(spacing: 10) {
                findingMetric(title: "Potential Issues", count: counts.potentialIssues, color: .orange, icon: "exclamationmark.triangle.fill")
                findingMetric(title: "Nitpicks", count: counts.nitpicks, color: .blue, icon: "sparkles")
                findingMetric(title: "Refactor Suggestions", count: counts.refactorSuggestions, color: .mint, icon: "arrow.triangle.2.circlepath")
            }

            if counts.uncategorized > 0 {
                Text("\(counts.uncategorized) findings in other categories.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    Color.orange.opacity(0.08),
                    Color.clear,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(overlayRoundedBorder(color: Color.accentColor.opacity(0.28)))
    }

    func geometryDistributionBar(counts: FindingTypeCounts) -> some View {
        GeometryReader { proxy in
            let total = max(1, counts.categorizedTotal)
            let width = proxy.size.width
            let potentialWidth = width * CGFloat(counts.potentialIssues) / CGFloat(total)
            let nitpickWidth = width * CGFloat(counts.nitpicks) / CGFloat(total)
            let refactorWidth = width * CGFloat(counts.refactorSuggestions) / CGFloat(total)

            HStack(spacing: 2) {
                if counts.potentialIssues > 0 {
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: potentialWidth)
                }
                if counts.nitpicks > 0 {
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: nitpickWidth)
                }
                if counts.refactorSuggestions > 0 {
                    Rectangle()
                        .fill(Color.mint)
                        .frame(width: refactorWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    func findingMetric(title: String, count: Int, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text("\(count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func findingTypeCounts(from findings: [ReviewFinding]) -> FindingTypeCounts {
        var potentialIssues = 0
        var nitpicks = 0
        var refactorSuggestions = 0
        var uncategorized = 0

        for finding in findings {
            let normalizedType = normalizedFindingType(for: finding)
            if normalizedType.contains("potential_issue") {
                potentialIssues += 1
            } else if normalizedType.contains("nitpick") {
                nitpicks += 1
            } else if normalizedType.contains("refactor_suggestion") {
                refactorSuggestions += 1
            } else {
                uncategorized += 1
            }
        }

        return FindingTypeCounts(
            potentialIssues: potentialIssues,
            nitpicks: nitpicks,
            refactorSuggestions: refactorSuggestions,
            uncategorized: uncategorized
        )
    }

    func normalizedFindingType(for finding: ReviewFinding) -> String {
        (finding.typeRaw ?? finding.typeDisplay)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    func progressSection(phases: [ReviewPhase], isRunning: Bool, hasFailed: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(ReviewPhase.allCases) { phase in
                HStack(spacing: 6) {
                    phaseIndicator(for: phase, phases: phases, isRunning: isRunning, hasFailed: hasFailed)
                    Text(phase.displayName)
                        .font(.caption)
                        .foregroundStyle(phaseTextColor(for: phase, phases: phases, isRunning: isRunning, hasFailed: hasFailed))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isPhaseCurrent(phase, phases: phases, isRunning: isRunning) ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(Capsule())
            }
            Spacer()
        }
        .opacity(phases.isEmpty ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: phases)
    }

    func errorCard(errorInfo: ReviewRunErrorInfo, nextAllowedRunAt: Date?) -> some View {
        let isInCooldown = nextAllowedRunAt.map { $0 > Date() } ?? false
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: errorInfo.isRateLimit ? "hourglass.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(errorInfo.isRateLimit ? "Rate Limit Reached" : "Review Failed")
                    .font(.headline)
            }

            if errorInfo.isRateLimit {
                if isInCooldown, let nextAllowedRunAt {
                    HStack(spacing: 4) {
                        Text("Try again in")
                        countdownLabel(until: nextAllowedRunAt)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                } else if let retryAfter = errorInfo.retryAfter, !retryAfter.isEmpty {
                    Text("Try again in \(retryAfter).")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            if let nextAllowedRunAt {
                let prefix = isInCooldown ? "Next request available at" : "Request available since"
                Text("\(prefix) \(Self.cooldownDateTimeFormatter.string(from: nextAllowedRunAt)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !errorInfo.isRateLimit {
                Text(errorInfo.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(overlayRoundedBorder(color: .red.opacity(0.2)))
    }

    func errorFallbackCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Review Failed")
                    .font(.headline)
            }
            Text(message)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(overlayRoundedBorder(color: .red.opacity(0.2)))
    }

    func resultsSection(
        command: String,
        findings: [ReviewFinding],
        rawOutput: String,
        selectedTab: Binding<Int>,
        showsLoadingPlaceholder: Bool = false
    ) -> some View {
        let combinedAIAgentPrompt = findings.isEmpty ? nil : ReviewParser.combinedAIAgentPrompt(from: findings)
        let shouldShowCombinedPromptTab = combinedAIAgentPrompt != nil

        return TabView(selection: selectedTab) {
            findingsView(
                command: command,
                findings: findings,
                rawOutput: rawOutput,
                showsLoadingPlaceholder: showsLoadingPlaceholder
            )
            .tabItem { Text("Findings") }
            .tag(0)

            rawOutputView(rawOutput: rawOutput)
                .tabItem { Text("Raw Output") }
                .tag(1)

            if let combinedAIAgentPrompt {
                combinedPromptView(
                    prompt: combinedAIAgentPrompt,
                    sourceCount: findings.compactMap(\.aiPrompt).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
                    shouldAutoExpandInPromptOnly: commandContainsFlag(command, long: "--prompt-only"),
                    forceExpanded: selectedTab.wrappedValue == 2
                )
                .tabItem { Text("AI Agent Prompt") }
                .tag(2)
            }
        }
        .onAppear {
            if !shouldShowCombinedPromptTab, selectedTab.wrappedValue == 2 {
                selectedTab.wrappedValue = 0
            }
        }
        .onChange(of: shouldShowCombinedPromptTab) { _, isShown in
            if !isShown, selectedTab.wrappedValue == 2 {
                selectedTab.wrappedValue = 0
            }
        }
    }

    func findingsView(command: String, findings: [ReviewFinding], rawOutput: String, showsLoadingPlaceholder: Bool) -> some View {
        let completion = ReviewParser.parseCompletionSummary(from: rawOutput)
        let hasNoFindingsResult = completion?.hasNoFindings == true
        let hasAnyOutput = !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shouldAutoExpandAgentPrompts = commandContainsFlag(command, long: "--prompt-only")
        return VStack(alignment: .leading, spacing: 8) {
            if findings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if showsLoadingPlaceholder {
                        Text(loadingRabbitASCII)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("CodeRabbit is reviewing your code...")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    } else if hasNoFindingsResult {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 108, weight: .bold))
                                .foregroundStyle(.green)
                            Text(findingsEmptyStateText(hasNoFindingsResult: true, hasAnyOutput: hasAnyOutput))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.green)
                            Text("Nothing to complain about in this review.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text(findingsEmptyStateText(hasNoFindingsResult: false, hasAnyOutput: hasAnyOutput))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    (showsLoadingPlaceholder ? Color.accentColor : (hasNoFindingsResult ? Color.green : Color.secondary))
                        .opacity(0.08)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if !findings.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !showsLoadingPlaceholder, completion != nil {
                            findingsSummaryCard(findings: findings)
                        }

                        ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 16) {
                                    Text("Finding \(index + 1)")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(severityColor(finding.severity))
                                        .foregroundStyle(.white)
                                        .clipShape(.capsule)
                                    HStack(spacing: 6) {
                                        Text(primaryTypeLabel(for: finding))
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(severityColor(finding.severity).opacity(0.2))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))

                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 8))
                                            .foregroundStyle(severityColor(finding.severity))
                                    }
                                }

                                if let location = locationText(for: finding) {
                                    Text(location)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text(finding.commentText)

                                if let proposedFix = finding.proposedFix {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            if let emoji = proposedFixEmoji(for: finding) {
                                                Text(emoji)
                                                    .font(.caption)
                                            }
                                            Text(proposedFixTitle(for: finding))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Button("Copy") {
                                                let text = proposedFix.lines.map(\.text).joined(separator: "\n")
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(text, forType: .string)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                        diffBlockView(proposedFix)
                                    }
                                }

                                if let aiPrompt = finding.aiPrompt, !aiPrompt.isEmpty {
                                    let key = promptKey(for: finding)
                                    VStack(alignment: .leading, spacing: 6) {
                                        if shouldAutoExpandAgentPrompts {
                                            HStack(spacing: 6) {
                                                Image(systemName: "chevron.down")
                                                    .font(.caption2)
                                                Text("Prompt for AI Agent")
                                                Spacer()
                                            }
                                        } else {
                                            Button {
                                                togglePrompt(forKey: key)
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: isPromptExpanded(forKey: key) ? "chevron.down" : "chevron.right")
                                                        .font(.caption2)
                                                    Text("Prompt for AI Agent")
                                                    Spacer()
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }

                                        if shouldAutoExpandAgentPrompts || isPromptExpanded(forKey: key) {
                                            VStack(alignment: .leading, spacing: 8) {
                                                codeBlock(aiPrompt)
                                                Button("Copy") {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(aiPrompt, forType: .string)
                                                }
                                                .buttonStyle(.bordered)
                                            }
                                        }
                                    }
                                }

                                if let appliesTo = finding.appliesTo, !appliesTo.isEmpty {
                                    Text("Also applies to: \(appliesTo)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func combinedPromptView(
        prompt: String,
        sourceCount: Int,
        shouldAutoExpandInPromptOnly: Bool,
        forceExpanded: Bool
    ) -> some View {
        ScrollView {
            combinedPromptCard(
                prompt: prompt,
                sourceCount: sourceCount,
                shouldAutoExpandInPromptOnly: shouldAutoExpandInPromptOnly,
                forceExpanded: forceExpanded
            )
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func combinedPromptCard(
        prompt: String,
        sourceCount: Int,
        shouldAutoExpandInPromptOnly: Bool,
        forceExpanded: Bool
    ) -> some View {
        let key = combinedPromptKey(for: prompt)
        let isExpanded = shouldAutoExpandInPromptOnly || forceExpanded || isPromptExpanded(forKey: key)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack.badge.person.crop.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Combined Prompt for AI Agent")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(sourceCount) prompt\(sourceCount == 1 ? "" : "s")")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.18))
                    .clipShape(Capsule())
            }

            if shouldAutoExpandInPromptOnly {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                    Text("Auto-expanded in prompt-only mode")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if !forceExpanded {
                Button {
                    togglePrompt(forKey: key)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isPromptExpanded(forKey: key) ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("Prompt Bundle")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    codeBlock(prompt)
                    Button("Copy Combined Prompt") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(prompt, forType: .string)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(overlayRoundedBorder(color: .accentColor.opacity(0.35)))
    }

    func rawOutputView(rawOutput: String) -> some View {
        ScrollView {
            Text(rawOutput.isEmpty ? "No output yet. Run a review to stream logs here." : rawOutput)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
        }
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var isRunning: Bool {
        runner.recoverInterruptedRunIfNeeded()
        return runner.isActivelyRunning
    }

    var isLiveRunFailed: Bool {
        if case .failed = runner.status { return true }
        return false
    }

    @ViewBuilder
    var runActionButton: some View {
        if !isRunning, let nextAllowedRunAt = runner.nextAllowedRunAt, nextAllowedRunAt > Date() {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                runActionButton(now: context.date)
            }
        } else {
            runActionButton(now: Date())
        }
    }

    func runActionButton(now: Date) -> some View {
        Button {
            forceShowNewReviewTriggerPage = false
            runner.runReview()
        } label: {
            runButtonLabel(now: now)
                .font(.title3)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isRunButtonDisabled(now: now))
        .keyboardShortcut(.return, modifiers: [.command])
    }

    func isRunButtonDisabled(now: Date) -> Bool {
        if isRunning { return true }
        if runner.selectedFolderPath.isEmpty { return true }
        switch normalizedComparisonBaseMode(comparisonBaseMode) {
        case .automatic:
            break
        case .baseBranch:
            if comparisonBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        case .baseCommit:
            if comparisonBaseCommit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        }
        if let nextAllowedRunAt = runner.nextAllowedRunAt {
            return nextAllowedRunAt > now
        }
        return false
    }

    @ViewBuilder
    func runButtonLabel(now: Date) -> some View {
        if isRunning {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Review Running")
                    .fontWeight(.bold)
            }
        } else if let nextAllowedRunAt = runner.nextAllowedRunAt, nextAllowedRunAt > now {
            HStack(spacing: 10) {
                Image(systemName: "clock.fill")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Retry in")
                        .font(.caption)
                    Text(Self.countdownString(until: nextAllowedRunAt, relativeTo: now))
                        .monospacedDigit()
                        .fontWeight(.bold)
                }
            }
        } else {
            Image(systemName: "play.fill")

            Text("Run Review")
                .fontWeight(.bold)
        }
    }

    var statusText: String {
        switch runner.status {
        case .idle:
            return "Idle"
        case .running:
            return "Running review..."
        case let .completed(code):
            if code == 0, let summary = ReviewParser.parseCompletionSummary(from: runner.rawOutput) {
                if summary.hasNoFindings {
                    return "No findings. Excellent work!"
                }
                if let count = summary.findingCount {
                    return "Review completed: \(count) finding\(count == 1 ? "" : "s")"
                }
                return "Completed successfully"
            }
            return code == 0 ? "Completed successfully" : "Completed with exit code \(code)"
        case let .failed(message):
            if let errorInfo = runner.runErrorInfo, errorInfo.isRateLimit {
                if let retryAfter = errorInfo.retryAfter, !retryAfter.isEmpty {
                    return "Rate limit reached. Try again in \(retryAfter)."
                }
                return "Rate limit reached."
            }
            return "Failed: \(message)"
        }
    }

    var statusColor: Color {
        switch runner.status {
        case .idle: return .secondary
        case .running: return .accentColor
        case let .completed(code): return code == 0 ? .green : .orange
        case .failed: return .red
        }
    }

    func historyStatusColor(_ status: String) -> Color {
        let lowered = status.lowercased()
        if lowered.contains("failed") || lowered.contains("error") || lowered.contains("rate limit") {
            return .red
        }
        if lowered.contains("exit code") {
            return .orange
        }
        return .green
    }

    func severityColor(_ severity: ReviewSeverity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .accentColor
        }
    }

    func phaseIndicator(for phase: ReviewPhase, phases: [ReviewPhase], isRunning: Bool, hasFailed: Bool) -> some View {
        Group {
            if isPhaseCurrent(phase, phases: phases, isRunning: isRunning) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 10, height: 10)
            } else if isPhaseFailed(phase, phases: phases, hasFailed: hasFailed) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if isPhaseCompleted(phase, phases: phases) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    func isPhaseCompleted(_ phase: ReviewPhase, phases: [ReviewPhase]) -> Bool {
        phases.contains(phase)
    }

    func isPhaseCurrent(_ phase: ReviewPhase, phases: [ReviewPhase], isRunning: Bool) -> Bool {
        guard isRunning else { return false }
        let latestPhase = phases.last(where: { $0 != .complete }) ?? .starting
        return latestPhase == phase && phase != .complete
    }

    func isPhaseFailed(_ phase: ReviewPhase, phases: [ReviewPhase], hasFailed: Bool) -> Bool {
        guard hasFailed else { return false }
        guard phase != .complete else { return false }
        guard !phases.contains(phase) else { return false }

        let orderedPhases = ReviewPhase.allCases.filter { $0 != .complete }
        let latestCompleted = phases.last(where: { $0 != .complete })
        guard let latestCompleted,
              let latestIndex = orderedPhases.firstIndex(of: latestCompleted),
              let phaseIndex = orderedPhases.firstIndex(of: phase)
        else { return false }

        return phaseIndex > latestIndex
    }

    func phaseTextColor(for phase: ReviewPhase, phases: [ReviewPhase], isRunning: Bool, hasFailed: Bool) -> Color {
        if isPhaseCompleted(phase, phases: phases) || isPhaseCurrent(phase, phases: phases, isRunning: isRunning) {
            return .primary
        }
        if isPhaseFailed(phase, phases: phases, hasFailed: hasFailed) {
            return .red
        }
        return .secondary
    }

    func isPromptExpanded(forKey key: String) -> Bool {
        expandedPromptKeys.contains(key)
    }

    func togglePrompt(forKey key: String) {
        if expandedPromptKeys.contains(key) {
            expandedPromptKeys.remove(key)
        } else {
            expandedPromptKeys.insert(key)
        }
    }

    func primaryTypeLabel(for finding: ReviewFinding) -> String {
        let source = finding.typeRaw ?? finding.typeDisplay
        return normalizeTypeLabel(source)
    }

    func proposedFixTitle(for finding: ReviewFinding) -> String {
        let trimmed = finding.proposedFixTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Proposed fix" : trimmed
    }

    func proposedFixEmoji(for finding: ReviewFinding) -> String? {
        let trimmed = finding.proposedFixEmoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func diffBlockView(_ block: ReviewDiffBlock) -> some View {
        Text(diffAttributedText(for: block))
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .textSelection(.enabled)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
    }

    func diffAttributedText(for block: ReviewDiffBlock) -> AttributedString {
        var output = AttributedString()

        for (index, line) in block.lines.enumerated() {
            var attributedLine = AttributedString(line.text)
            attributedLine.foregroundColor = diffForegroundNSColor(for: line.kind)
            attributedLine.backgroundColor = diffBackgroundNSColor(for: line.kind)
            output += attributedLine

            if index < block.lines.count - 1 {
                output += AttributedString("\n")
            }
        }

        return output
    }

    func codeBlock(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .textSelection(.enabled)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
    }

    func overlayRoundedBorder(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(color, lineWidth: 1)
    }

    func diffForegroundNSColor(for kind: ReviewDiffLineKind) -> NSColor {
        switch kind {
        case .added:
            return .systemGreen
        case .removed:
            return .systemRed
        case .meta:
            return .secondaryLabelColor
        case .context:
            return .labelColor
        }
    }

    func diffBackgroundNSColor(for kind: ReviewDiffLineKind) -> NSColor {
        switch kind {
        case .added:
            return NSColor.systemGreen.withAlphaComponent(0.12)
        case .removed:
            return NSColor.systemRed.withAlphaComponent(0.12)
        case .meta:
            return NSColor.secondaryLabelColor.withAlphaComponent(0.08)
        case .context:
            return .clear
        }
    }
}
