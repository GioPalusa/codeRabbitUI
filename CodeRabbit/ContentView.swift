//
//  ContentView.swift
//  CodeRabbit
//
//  Created by Giovanni Palusa on 2026-03-03.
//

import AppKit
import SwiftUI

private enum ReviewSelection: Hashable {
	case current
	case history(UUID)
}

private enum ReviewOutputMode: String {
	case full
	case promptOnly
}

private enum ComparisonBaseMode: String {
	case automatic
	case baseBranch
	case baseCommit
}

private struct HistoryFolderGroup: Identifiable {
	let folderPath: String
	let items: [ReviewHistoryItem]

	var id: String {
		folderPath
	}
}

struct ContentView: View {
	@EnvironmentObject private var historyStore: ReviewHistoryStore

	@StateObject private var runner = ReviewRunner()
	@State private var selectedLiveTab: Int = 0
	@State private var selectedHistoryTab: Int = 0
	@State private var expandedPromptKeys: Set<String> = []
	@State private var collapsedHistoryFolders: Set<String> = []
	@State private var lastSelectedProjectFolderPath: String = ""
	@State private var selection: ReviewSelection? = .current

	@AppStorage("coderabbitExecutablePath") private var coderabbitExecutablePath: String = ReviewRunner.defaultExecutablePath()
	@AppStorage("reviewOutputMode") private var reviewOutputMode: String = ReviewOutputMode.full.rawValue
	@AppStorage("reviewType") private var reviewType: String = "all"
	@AppStorage("comparisonBaseMode") private var comparisonBaseMode: String = ComparisonBaseMode.automatic.rawValue
	@AppStorage("comparisonBaseBranch") private var comparisonBaseBranch: String = ""
	@AppStorage("comparisonBaseCommit") private var comparisonBaseCommit: String = ""
	@AppStorage("reviewConfigFilesJSON") private var reviewConfigFilesJSON: String = "[]"
	@AppStorage("selectedProjectFolderPath") private var selectedProjectFolderPath: String = ""
	@AppStorage("recentProjectFoldersJSON") private var recentProjectFoldersJSON: String = "[]"
	@State private var recentProjectFolders: [String] = []
	@State private var gitBranches: [String] = []
	@State private var isLoadingGitBranches: Bool = false
	@State private var gitBranchesRequestID: Int = 0
	@State private var gitBranchLookupFailed: Bool = false
	private let projectFolderBookmarkKey = ReviewRunner.projectFolderBookmarkKey
	private let addWorkspaceOptionTag = "__add_workspace__"

	var body: some View {
		HStack(spacing: 0) {
			sidebarView
			Divider()
			detailView
		}
		.onAppear {
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
			lastSelectedProjectFolderPath = selectedProjectFolderPath
			historyStore.purgeExpired()
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
		}
		.onChange(of: comparisonBaseBranch) { _, _ in
			applyComparisonBaseToRunner()
		}
		.onChange(of: comparisonBaseCommit) { _, _ in
			applyComparisonBaseToRunner()
		}
		.onChange(of: reviewConfigFilesJSON) { _, _ in
			runner.configFiles = parsedReviewConfigFiles
		}
		.onChange(of: runner.completedRunID) { _, newValue in
			guard let newValue else { return }
			historyStore.add(
				id: newValue,
				createdAt: runner.currentRunStartedAt ?? Date(),
				command: runner.command,
				folderPath: runner.selectedFolderPath,
				rawOutput: runner.rawOutput,
				findings: runner.findings,
				phases: runner.phases,
				statusLabel: statusText
			)
		}
		.onChange(of: runner.currentRunID) { _, newValue in
			guard let newValue else { return }
			selection = .history(newValue)
			selectedHistoryTab = 0
			collapsedHistoryFolders.remove(normalizedFolderPath(runner.selectedFolderPath))
		}
	}

	private var sidebarView: some View {
		List {
			Button {
				selection = .current
				runner.prepareForNewReview()
				selectedLiveTab = 0
				expandedPromptKeys.removeAll()
			} label: {
				freshReviewButtonLabel
			}
			.buttonStyle(.plain)
			.listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
			.listRowBackground(Color.clear)

			Section("History (30 days)") {
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
									.frame(maxWidth: .infinity, alignment: .leading)
									.contentShape(Rectangle())
								}
								.buttonStyle(.plain)
								.listRowBackground(selection == rowSelection ? Color.accentColor.opacity(0.2) : Color.clear)
							}
						},
						label: {
							HStack(spacing: 6) {
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
		.frame(minWidth: 280, idealWidth: 300, maxWidth: 320)
	}

	private var freshReviewButtonLabel: some View {
		HStack(spacing: 10) {
			ZStack {
				Circle()
					.fill(Color.accentColor.opacity(0.18))
					.frame(width: 28, height: 28)
				Image(systemName: "square.and.pencil")
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(Color.accentColor)
			}

			VStack(alignment: .leading, spacing: 1) {
				Text("New Review")
					.font(.subheadline.weight(.semibold))
				Text("Start a clean review run")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 8)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.fill(Color.accentColor.opacity(selection == .current ? 0.18 : 0.08))
		)
		.overlay(
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.stroke(Color.accentColor.opacity(selection == .current ? 0.35 : 0.2), lineWidth: 1)
		)
		.contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
	}

	@ViewBuilder
	private var detailView: some View {
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

	private var liveDetailView: some View {
		Group {
			if showsNewReviewTriggerPage {
				newReviewTriggerView
			} else {
				VStack(spacing: 12) {
					headerSection(title: "New Review", subtitle: statusText, subtitleColor: statusColor)
					controlsSection
					progressSection(phases: runner.phases, isRunning: isRunning, hasFailed: isLiveRunFailed)
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

	private var showsNewReviewTriggerPage: Bool {
		if isRunning { return false }
		if !runner.phases.isEmpty { return false }
		if !runner.rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
		if !runner.findings.isEmpty { return false }
		if case .failed = runner.status { return false }
		return true
	}

	private var newReviewTriggerView: some View {
		ZStack(alignment: .topTrailing) {
			LinearGradient(
				colors: [
					Color(red: 0.20, green: 0.10, blue: 0.04),
					Color(red: 0.36, green: 0.17, blue: 0.06),
					Color(red: 0.16, green: 0.07, blue: 0.03),
				],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			)
			.ignoresSafeArea()

			Circle()
				.fill(Color.white.opacity(0.08))
				.frame(width: 280, height: 280)
				.blur(radius: 10)
				.offset(x: -260, y: -180)

			Circle()
				.fill(Color.orange.opacity(0.22))
				.frame(width: 220, height: 220)
				.blur(radius: 18)
				.offset(x: 250, y: 180)

			VStack {
				Spacer()
				VStack(alignment: .leading, spacing: 18) {
					Image("coderabbitlogo")
						.resizable()
						.scaledToFit()
						.frame(maxWidth: 600)

					VStack(alignment: .leading, spacing: 6) {
						Text("Let's review your code!")
							.font(.system(size: 34, weight: .heavy, design: .rounded))
							.foregroundStyle(.white)
						Text("Pick settings, hit start, then we switch to the full review workspace.")
							.font(.subheadline)
							.foregroundStyle(Color.white.opacity(0.85))
					}

					VStack(spacing: 14) {
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
								.foregroundStyle(Color.white.opacity(0.95))
								.frame(maxWidth: .infinity, alignment: .leading)
								.textSelection(.enabled)
						}
					}
					.padding(16)
					.background(Color.orange.opacity(0.14))
					.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
					.overlay(
						RoundedRectangle(cornerRadius: 18, style: .continuous)
							.stroke(Color.white.opacity(0.24), lineWidth: 1)
					)

					HStack {
						Spacer()
						runActionButton
							.tint(Color.orange)
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
					.foregroundStyle(.white)
			}
			.padding(.top, 20)
			.padding(.trailing, 20)
			.buttonStyle(.plain)
		}
		.frame(minWidth: 760, minHeight: 680)
	}

	private func triggerSettingRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(title)
				.font(.caption.weight(.semibold))
				.foregroundStyle(Color.white.opacity(0.72))
			content()
		}
	}

	private func historyDetailView(_ item: ReviewHistoryItem) -> some View {
		VStack(spacing: 12) {
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

			progressSection(phases: item.phases, isRunning: false, hasFailed: historyHasFailed(item))
			if let runErrorInfo = ReviewParser.parseRunErrorInfo(from: item.rawOutput) {
				errorCard(errorInfo: runErrorInfo, nextAllowedRunAt: historyNextAllowedRunAt(for: runErrorInfo))
			}
			Divider()
			resultsSection(
				command: item.command,
				findings: resolvedFindings(for: item),
				rawOutput: item.rawOutput,
				selectedTab: $selectedHistoryTab,
				showsLoadingPlaceholder: runner.currentRunID == item.id
			)
		}
		.padding(16)
		.frame(minWidth: 760, minHeight: 680)
	}

	private var missingHistoryView: some View {
		VStack {
			Text("This review is no longer available.")
				.foregroundStyle(.secondary)
			Button("Back to New Review") {
				selection = .current
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private func headerSection(title: String, subtitle: String, subtitleColor: Color) -> some View {
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

	private var controlsSection: some View {
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

	private func progressSection(phases: [ReviewPhase], isRunning: Bool, hasFailed: Bool) -> some View {
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

	private func errorCard(errorInfo: ReviewRunErrorInfo, nextAllowedRunAt: Date?) -> some View {
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

	private func errorFallbackCard(message: String) -> some View {
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

	private func resultsSection(
		command: String,
		findings: [ReviewFinding],
		rawOutput: String,
		selectedTab: Binding<Int>,
		showsLoadingPlaceholder: Bool = false
	) -> some View {
		TabView(selection: selectedTab) {
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
		}
	}

	private func findingsView(command: String, findings: [ReviewFinding], rawOutput: String, showsLoadingPlaceholder: Bool) -> some View {
		let completion = ReviewParser.parseCompletionSummary(from: rawOutput)
		let hasNoFindingsResult = completion?.hasNoFindings == true
		let hasAnyOutput = !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		let shouldAutoExpandAgentPrompts = commandContainsFlag(command, long: "--prompt-only")
		let combinedAIAgentPrompt = ReviewParser.combinedAIAgentPrompt(from: findings)
		let aiPromptCount = findings.compactMap(\.aiPrompt).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
		return VStack(alignment: .leading, spacing: 8) {
			Text("Parsed Findings: \(findings.count)")
				.font(.headline)
			if findings.isEmpty {
				VStack(alignment: .leading, spacing: 8) {
					if showsLoadingPlaceholder {
						Text(loadingRabbitASCII)
							.font(.system(.caption, design: .monospaced))
							.foregroundStyle(Color.accentColor)
						HStack(spacing: 8) {
							ProgressView()
								.controlSize(.small)
							Text("Rabbit is reviewing your code...")
								.font(.subheadline.weight(.semibold))
								.foregroundStyle(Color.accentColor)
						}
					} else {
						HStack(spacing: 8) {
							Image(systemName: hasNoFindingsResult ? "sparkles" : "info.circle")
								.foregroundStyle(hasNoFindingsResult ? .green : .secondary)
							Text(findingsEmptyStateText(hasNoFindingsResult: hasNoFindingsResult, hasAnyOutput: hasAnyOutput))
								.font(.subheadline.weight(.semibold))
								.foregroundStyle(hasNoFindingsResult ? .green : .secondary)
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
						ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
							VStack(alignment: .leading, spacing: 8) {
								HStack(spacing: 16) {
									Text("Finding \(index + 1)")
										.font(.caption.bold())
										.padding(.horizontal, 10)
										.padding(.vertical, 4)
										.background(severityColor(finding.severity))
										.foregroundStyle(.black)
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

						if let combinedAIAgentPrompt {
							combinedPromptCard(
								prompt: combinedAIAgentPrompt,
								sourceCount: aiPromptCount,
								shouldAutoExpand: shouldAutoExpandAgentPrompts
							)
						}
					}
					.padding(.vertical, 2)
				}
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	}

	private func combinedPromptCard(prompt: String, sourceCount: Int, shouldAutoExpand: Bool) -> some View {
		let key = combinedPromptKey(for: prompt)
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

			if shouldAutoExpand {
				HStack(spacing: 6) {
					Image(systemName: "chevron.down")
						.font(.caption2)
					Text("Auto-expanded in prompt-only mode")
					Spacer()
				}
				.font(.caption)
				.foregroundStyle(.secondary)
			} else {
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

			if shouldAutoExpand || isPromptExpanded(forKey: key) {
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

	private func rawOutputView(rawOutput: String) -> some View {
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

	private var isRunning: Bool {
		if case .running = runner.status { return true }
		return false
	}

	private var isLiveRunFailed: Bool {
		if case .failed = runner.status { return true }
		return false
	}

	@ViewBuilder
	private var runActionButton: some View {
		if !isRunning, let nextAllowedRunAt = runner.nextAllowedRunAt, nextAllowedRunAt > Date() {
			TimelineView(.periodic(from: .now, by: 1)) { context in
				runActionButton(now: context.date)
			}
		} else {
			runActionButton(now: Date())
		}
	}

	private func runActionButton(now: Date) -> some View {
		Button {
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

	private func isRunButtonDisabled(now: Date) -> Bool {
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
	private func runButtonLabel(now: Date) -> some View {
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
				.foregroundStyle(.black)

			Text("Run Review")
				.fontWeight(.bold)
				.foregroundStyle(.black)
		}
	}

	private var statusText: String {
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

	private var statusColor: Color {
		switch runner.status {
		case .idle: return .secondary
		case .running: return .accentColor
		case let .completed(code): return code == 0 ? .green : .orange
		case .failed: return .red
		}
	}

	private func historyStatusColor(_ status: String) -> Color {
		let lowered = status.lowercased()
		if lowered.contains("failed") || lowered.contains("error") || lowered.contains("rate limit") {
			return .red
		}
		if lowered.contains("exit code") {
			return .orange
		}
		return .green
	}

	private func severityColor(_ severity: ReviewSeverity) -> Color {
		switch severity {
		case .error: return .red
		case .warning: return .orange
		case .info: return .accentColor
		}
	}

	private func phaseIndicator(for phase: ReviewPhase, phases: [ReviewPhase], isRunning: Bool, hasFailed: Bool) -> some View {
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

	private func isPhaseCompleted(_ phase: ReviewPhase, phases: [ReviewPhase]) -> Bool {
		phases.contains(phase)
	}

	private func isPhaseCurrent(_ phase: ReviewPhase, phases: [ReviewPhase], isRunning: Bool) -> Bool {
		guard isRunning else { return false }
		let latestPhase = phases.last(where: { $0 != .complete }) ?? .starting
		return latestPhase == phase && phase != .complete
	}

	private func isPhaseFailed(_ phase: ReviewPhase, phases: [ReviewPhase], hasFailed: Bool) -> Bool {
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

	private func phaseTextColor(for phase: ReviewPhase, phases: [ReviewPhase], isRunning: Bool, hasFailed: Bool) -> Color {
		if isPhaseCompleted(phase, phases: phases) || isPhaseCurrent(phase, phases: phases, isRunning: isRunning) {
			return .primary
		}
		if isPhaseFailed(phase, phases: phases, hasFailed: hasFailed) {
			return .red
		}
		return .secondary
	}

	private func isPromptExpanded(forKey key: String) -> Bool {
		expandedPromptKeys.contains(key)
	}

	private func togglePrompt(forKey key: String) {
		if expandedPromptKeys.contains(key) {
			expandedPromptKeys.remove(key)
		} else {
			expandedPromptKeys.insert(key)
		}
	}

	private func primaryTypeLabel(for finding: ReviewFinding) -> String {
		let source = finding.typeRaw ?? finding.typeDisplay
		return normalizeTypeLabel(source)
	}

	private func proposedFixTitle(for finding: ReviewFinding) -> String {
		let trimmed = finding.proposedFixTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return trimmed.isEmpty ? "Proposed fix" : trimmed
	}

	private func proposedFixEmoji(for finding: ReviewFinding) -> String? {
		let trimmed = finding.proposedFixEmoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return trimmed.isEmpty ? nil : trimmed
	}

	private func diffBlockView(_ block: ReviewDiffBlock) -> some View {
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

	private func diffAttributedText(for block: ReviewDiffBlock) -> AttributedString {
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

	private func codeBlock(_ text: String) -> some View {
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

	private func overlayRoundedBorder(color: Color) -> some View {
		RoundedRectangle(cornerRadius: 10)
			.stroke(color, lineWidth: 1)
	}

	private func diffForegroundNSColor(for kind: ReviewDiffLineKind) -> NSColor {
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

	private func diffBackgroundNSColor(for kind: ReviewDiffLineKind) -> NSColor {
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

	private func pickFolder() {
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

	private func loadRecentProjectFolders() {
		guard let data = recentProjectFoldersJSON.data(using: .utf8) else {
			recentProjectFolders = []
			return
		}
		let decodedFolders = (try? JSONDecoder().decode([String].self, from: data)) ?? []
		recentProjectFolders = decodedFolders.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
	}

	private func rememberProjectFolder(_ folderPath: String) {
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

	private func folderMenuLabel(for folderPath: String) -> String {
		let folderName = URL(fileURLWithPath: folderPath).lastPathComponent
		if folderName.isEmpty {
			return folderPath
		}
		return "\(folderName) (\(folderPath))"
	}

	private var availableProjectFolders: [String] {
		let trimmedSelection = selectedProjectFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmedSelection.isEmpty || recentProjectFolders.contains(trimmedSelection) {
			return recentProjectFolders
		}
		return [trimmedSelection] + recentProjectFolders
	}

	private func normalizedReviewType(_ value: String) -> String {
		let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		switch lowered {
		case "committed", "uncommitted":
			return lowered
		default:
			return "all"
		}
	}

	private var parsedReviewConfigFiles: [String] {
		guard let data = reviewConfigFilesJSON.data(using: .utf8) else {
			return []
		}
		let decodedFiles = (try? JSONDecoder().decode([String].self, from: data)) ?? []
		return decodedFiles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
	}

	private var effectiveCommandPreview: String {
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

	private var selectedReviewCommand: String {
		switch normalizedReviewOutputMode(reviewOutputMode) {
		case .full:
			return "review --plain"
		case .promptOnly:
			return "review --prompt-only"
		}
	}

	private func normalizedReviewOutputMode(_ value: String) -> ReviewOutputMode {
		ReviewOutputMode(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .full
	}

	private func normalizedComparisonBaseMode(_ value: String) -> ComparisonBaseMode {
		ComparisonBaseMode(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .automatic
	}

	private func applyComparisonBaseToRunner() {
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

	private func refreshGitBranches(for folderPath: String) {
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
	private func comparisonBaseControls(isTriggerLayout: Bool) -> some View {
		let modeBinding = Binding(
			get: { normalizedComparisonBaseMode(comparisonBaseMode) },
			set: { comparisonBaseMode = $0.rawValue }
		)

		VStack {
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

	private func commandContainsFlag(_ command: String, long: String, short: String? = nil) -> Bool {
		let args = command.split(separator: " ").map(String.init)
		return args.contains(where: {
			$0 == long
				|| (short != nil && $0 == short)
				|| $0.hasPrefix("\(long)=")
		})
	}

	private func locationText(for finding: ReviewFinding) -> String? {
		guard let file = finding.file, !file.isEmpty else { return nil }
		guard let line = finding.line else { return file }
		if let lineEnd = finding.lineEnd, lineEnd != line {
			return "\(file):\(line)-\(lineEnd)"
		}
		return "\(file):\(line)"
	}

	private func historyTitle(for item: ReviewHistoryItem) -> String {
		let folderName = URL(fileURLWithPath: item.folderPath).lastPathComponent
		if folderName.isEmpty { return "Review" }
		return folderName
	}

	private func historyListSummary(for item: ReviewHistoryItem) -> (text: String, color: Color) {
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

	private var displayedHistoryItems: [ReviewHistoryItem] {
		if let inProgressHistoryItem {
			return [inProgressHistoryItem] + historyStore.items.filter { $0.id != inProgressHistoryItem.id }
		}
		return historyStore.items
	}

	private var inProgressHistoryItem: ReviewHistoryItem? {
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

	private func historyItem(for id: UUID) -> ReviewHistoryItem? {
		if inProgressHistoryItem?.id == id {
			return inProgressHistoryItem
		}
		return historyStore.items.first(where: { $0.id == id })
	}

	private var groupedHistoryItems: [HistoryFolderGroup] {
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

	private func isHistoryGroupExpandedBinding(for folderPath: String) -> Binding<Bool> {
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

	private func historyFolderName(for folderPath: String) -> String {
		let folderName = URL(fileURLWithPath: folderPath).lastPathComponent
		return folderName.isEmpty ? "Unknown Folder" : folderName
	}

	private func normalizedFolderPath(_ folderPath: String) -> String {
		let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? "/" : trimmed
	}

	private func normalizeTypeLabel(_ raw: String) -> String {
		let withSpaces = raw.replacingOccurrences(of: "_", with: " ")
		guard let first = withSpaces.first else { return raw }
		return first.uppercased() + withSpaces.dropFirst()
	}

	private func promptKey(for finding: ReviewFinding) -> String {
		[
			finding.file ?? "",
			String(finding.line ?? 0),
			String(finding.lineEnd ?? 0),
			finding.typeRaw ?? finding.typeDisplay,
			finding.aiPrompt ?? "",
		].joined(separator: "|")
	}

	private func combinedPromptKey(for prompt: String) -> String {
		"combined|\(prompt.count)|\(prompt.hashValue)"
	}

	private func resolvedFindings(for item: ReviewHistoryItem) -> [ReviewFinding] {
		let reparsed = ReviewParser.parse(from: item.rawOutput)
		if ReviewParser.parseRunErrorInfo(from: item.rawOutput) != nil {
			return []
		}
		return reparsed.isEmpty ? item.findings : reparsed
	}

	private func historyStatusLabel(for item: ReviewHistoryItem) -> String {
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

	private func historySubtitle(for item: ReviewHistoryItem) -> String {
		let dateText = Self.historyDateFormatter.string(from: item.createdAt)
		return "\(dateText) • \(historyStatusLabel(for: item))"
	}

	private static let historyDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .short
		formatter.timeStyle = .short
		return formatter
	}()

	private static let cooldownDateTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .medium
		return formatter
	}()

	private func countdownLabel(until date: Date) -> some View {
		TimelineView(.periodic(from: .now, by: 1)) { context in
			Text(Self.countdownString(until: date, relativeTo: context.date))
				.monospacedDigit()
		}
	}

	private static func countdownString(until date: Date, relativeTo now: Date) -> String {
		let remaining = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
		let minutes = remaining / 60
		let seconds = remaining % 60
		return String(format: "%02d:%02d", minutes, seconds)
	}

	private var loadingRabbitASCII: String {
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

	private func findingsEmptyStateText(hasNoFindingsResult: Bool, hasAnyOutput: Bool) -> String {
		if hasNoFindingsResult {
			return "No findings. Excellent review!"
		}
		if !hasAnyOutput {
			return "Run a review to see findings."
		}
		return "No findings parsed for this run."
	}

	private func historyNextAllowedRunAt(for errorInfo: ReviewRunErrorInfo) -> Date? {
		guard errorInfo.isRateLimit, let retryAfterSeconds = errorInfo.retryAfterSeconds else { return nil }
		return (errorInfo.occurredAt ?? Date()).addingTimeInterval(retryAfterSeconds)
	}

	private func historyHasFailed(_ item: ReviewHistoryItem) -> Bool {
		let loweredStatus = historyStatusLabel(for: item).lowercased()
		return loweredStatus.contains("failed")
			|| loweredStatus.contains("error")
			|| loweredStatus.contains("rate limit")
	}
}
