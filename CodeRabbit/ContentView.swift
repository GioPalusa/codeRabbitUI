//
//  ContentView.swift
//  CodeRabbit
//
//  Created by Giovanni Palusa on 2026-03-03.
//

import AppKit
import SwiftUI
import UserNotifications

struct ContentView: View {
    @EnvironmentObject var historyStore: ReviewHistoryStore
    @Environment(\.colorScheme) var colorScheme

    @StateObject var runner = ReviewRunner()
    @State var selectedLiveTab: Int = 0
    @State var selectedHistoryTab: Int = 0
    @State var expandedPromptKeys: Set<String> = []
    @State var collapsedHistoryFolders: Set<String> = []
    @State var lastSelectedProjectFolderPath: String = ""
    @State var forceShowNewReviewTriggerPage: Bool = false
    @State var selection: ReviewSelection? = .current

    @AppStorage("coderabbitExecutablePath") var coderabbitExecutablePath: String = ReviewRunner.defaultExecutablePath()
    @AppStorage("reviewOutputMode") var reviewOutputMode: String = ReviewOutputMode.full.rawValue
    @AppStorage("reviewType") var reviewType: String = "all"
    @AppStorage("comparisonBaseMode") var comparisonBaseMode: String = ComparisonBaseMode.automatic.rawValue
    @AppStorage("comparisonBaseBranch") var comparisonBaseBranch: String = ""
    @AppStorage("comparisonBaseCommit") var comparisonBaseCommit: String = ""
    @AppStorage("reviewConfigFilesJSON") var reviewConfigFilesJSON: String = "[]"
    @AppStorage("selectedProjectFolderPath") var selectedProjectFolderPath: String = ""
    @AppStorage("recentProjectFoldersJSON") var recentProjectFoldersJSON: String = "[]"
    @AppStorage("sidebarShowNewReview") var sidebarShowNewReview: Bool = true
    @AppStorage("sidebarShowHistory") var sidebarShowHistory: Bool = true
    @AppStorage("sidebarPrimarySection") var sidebarPrimarySectionRaw: String = SidebarPrimarySection.newReview.rawValue
    @State var recentProjectFolders: [String] = []
    @State var gitBranches: [String] = []
    @State var isLoadingGitBranches: Bool = false
    @State var gitBranchesRequestID: Int = 0
    @State var gitBranchLookupFailed: Bool = false
    @State var gitChangeSummary: GitChangeSummary?
    @State var isLoadingGitChangeSummary: Bool = false
    @State var gitChangeSummaryRequestID: Int = 0
    @State var activeRunCommandPreview: String?
    @State var splitViewVisibility: NavigationSplitViewVisibility = .all
    let projectFolderBookmarkKey = ReviewRunner.projectFolderBookmarkKey
    let addWorkspaceOptionTag = "__add_workspace__"

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            sidebarView
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 340)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.automatic)
        .toolbar(.hidden, for: .windowToolbar)
        .onAppear {
            runner.recoverInterruptedRunIfNeeded()
            sidebarPrimarySectionRaw = SidebarPrimarySection(rawValue: sidebarPrimarySectionRaw)?.rawValue ?? SidebarPrimarySection.newReview.rawValue
            if !sidebarShowNewReview, !sidebarShowHistory {
                sidebarShowHistory = true
            }
            coderabbitExecutablePath = ReviewRunner.normalizeStoredExecutablePath(coderabbitExecutablePath)
            reviewOutputMode = normalizedReviewOutputMode(reviewOutputMode).rawValue
            comparisonBaseMode = normalizedComparisonBaseMode(comparisonBaseMode).rawValue
            loadRecentProjectFolders()
            if !selectedProjectFolderPath.isEmpty {
                rememberProjectFolder(selectedProjectFolderPath)
            } else if let firstFolder = recentProjectFolders.first {
                selectedProjectFolderPath = firstFolder
            }
            runner.executablePathOverride = coderabbitExecutablePath
            runner.command = selectedReviewCommand
            runner.reviewType = normalizedReviewType(reviewType)
            runner.configFiles = parsedReviewConfigFiles
            runner.selectedFolderPath = selectedProjectFolderPath
            applyComparisonBaseToRunner()
            refreshGitBranches(for: selectedProjectFolderPath)
            refreshGitChangeSummary(for: selectedProjectFolderPath)
            lastSelectedProjectFolderPath = selectedProjectFolderPath
            historyStore.purgeExpired()
            runner.restoreRateLimitCooldown(from: historyStore.items)
            requestNotificationAuthorizationIfNeeded()
        }
        .onChange(of: coderabbitExecutablePath) { _, newValue in
            runner.executablePathOverride = newValue
        }
        .onChange(of: selectedProjectFolderPath) { _, newValue in
            if newValue == addWorkspaceOptionTag {
                selectedProjectFolderPath = lastSelectedProjectFolderPath
                pickFolder()
                return
            }
            runner.selectedFolderPath = newValue
            rememberProjectFolder(newValue)
            refreshGitBranches(for: newValue)
            refreshGitChangeSummary(for: newValue)
            lastSelectedProjectFolderPath = newValue
        }
        .onChange(of: reviewOutputMode) { _, newValue in
            reviewOutputMode = normalizedReviewOutputMode(newValue).rawValue
            runner.command = selectedReviewCommand
        }
        .onChange(of: reviewType) { _, newValue in
            runner.reviewType = normalizedReviewType(newValue)
        }
        .onChange(of: comparisonBaseMode) { _, newValue in
            comparisonBaseMode = normalizedComparisonBaseMode(newValue).rawValue
            applyComparisonBaseToRunner()
            refreshGitChangeSummary(for: selectedProjectFolderPath)
        }
        .onChange(of: comparisonBaseBranch) { _, _ in
            applyComparisonBaseToRunner()
            refreshGitChangeSummary(for: selectedProjectFolderPath)
        }
        .onChange(of: comparisonBaseCommit) { _, _ in
            applyComparisonBaseToRunner()
            refreshGitChangeSummary(for: selectedProjectFolderPath)
        }
        .onChange(of: reviewConfigFilesJSON) { _, _ in
            runner.configFiles = parsedReviewConfigFiles
        }
        .onChange(of: sidebarPrimarySectionRaw) { _, newValue in
            sidebarPrimarySectionRaw = SidebarPrimarySection(rawValue: newValue)?.rawValue ?? SidebarPrimarySection.newReview.rawValue
        }
        .onChange(of: sidebarShowNewReview) { _, _ in
            if !sidebarShowNewReview, !sidebarShowHistory {
                sidebarShowHistory = true
            }
        }
        .onChange(of: sidebarShowHistory) { _, _ in
            if !sidebarShowNewReview, !sidebarShowHistory {
                sidebarShowNewReview = true
            }
        }
        .onChange(of: runner.completedRunID) { _, newValue in
            guard let newValue else { return }
            let trimmedActiveRunCommand = activeRunCommandPreview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let persistedCommand = trimmedActiveRunCommand.isEmpty ? effectiveCommandPreview : trimmedActiveRunCommand
            historyStore.add(
                id: newValue,
                createdAt: runner.currentRunStartedAt ?? Date(),
                command: persistedCommand,
                folderPath: runner.selectedFolderPath,
                rawOutput: runner.rawOutput,
                findings: runner.findings,
                phases: runner.phases,
                statusLabel: statusText
            )
            activeRunCommandPreview = nil
        }
        .onChange(of: runner.currentRunID) { _, newValue in
            guard let newValue else { return }
            activeRunCommandPreview = effectiveCommandPreview
            selection = .history(newValue)
            selectedHistoryTab = 0
            collapsedHistoryFolders.remove(normalizedFolderPath(runner.selectedFolderPath))
        }
        .onChange(of: runner.completedRequestID) { _, newValue in
            guard newValue != nil else { return }
            requestDockBounceForCompletedReview()
            sendReviewCompletionNotification()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            runner.recoverInterruptedRunIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            runner.recoverInterruptedRunIfNeeded()
        }
    }
}
