import Foundation
import Combine
import Darwin

@MainActor
final class ReviewRunner: ObservableObject {
	@Published var command: String = ReviewRunner.defaultCommand()
	@Published var reviewType: String = "all"
	@Published var configFiles: [String] = []
	@Published var baseBranch: String = ""
	@Published var baseCommit: String = ""
	@Published var executablePathOverride: String = ""
	@Published var selectedFolderPath: String = ""
	@Published var rawOutput: String = ""
	@Published var findings: [ReviewFinding] = []
	@Published var phases: [ReviewPhase] = []
	@Published var status: ReviewStatus = .idle
	@Published private(set) var runErrorInfo: ReviewRunErrorInfo?
	@Published private(set) var nextAllowedRunAt: Date?
	@Published private(set) var currentRunID: UUID?
	@Published private(set) var currentRunStartedAt: Date?
	@Published private(set) var completedRunID: UUID?

	private var process: Process?
	private var securityScopedExecutableURL: URL?
	private var securityScopedProjectFolderURL: URL?
	private let executableBookmarkKey = "coderabbitExecutableBookmark"
	static let projectFolderBookmarkKey = "selectedProjectFolderBookmark"

	static func defaultExecutablePath() -> String {
		realUserHomeDirectoryPath()
			.appending("/.local/bin/coderabbit")
	}

	static func normalizeStoredExecutablePath(_ rawValue: String) -> String {
		let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return defaultExecutablePath() }

		// Guard against accidentally storing a PATH-like value.
		let components = trimmed.split(separator: ":").map(String.init)
		if components.count > 1 {
			if let candidate = components.first(where: { looksLikeExecutablePath($0) }) {
				return normalizedUserPath(candidate)
			}
			return defaultExecutablePath()
		}

		let normalized = normalizedUserPath(trimmed)
		if let remappedContainerPath = remappedContainerExecutablePath(normalized) {
			return remappedContainerPath
		}
		let defaultPath = defaultExecutablePath()
		if isForeignHomeLocalCoderabbitPath(normalized) {
			return defaultPath
		}
		return normalized
	}

	static func defaultCommand() -> String {
		"review --plain"
	}

	func runReview() {
		Task { [weak self] in
			await self?.runReviewAsync()
		}
	}

	private func runReviewAsync() async {
		if case .running = status {
			return
		}

		if let nextAllowedRunAt, Date() < nextAllowedRunAt {
			let secondsLeft = Int(nextAllowedRunAt.timeIntervalSinceNow.rounded(.up))
			let minutes = max(0, secondsLeft / 60)
			let seconds = max(0, secondsLeft % 60)
			status = .failed("Rate limit active. Try again in \(minutes)m \(seconds)s.")
			return
		}

		guard !selectedFolderPath.isEmpty else {
			status = .failed("Pick a project folder before running a review.")
			return
		}

		let overridePath = normalizedExecutablePath(executablePathOverride) ?? ""
		logDebug("Override path: \(overridePath.isEmpty ? "empty" : overridePath)")
		logDebug("PATH: \(buildPortablePath(basePath: ProcessInfo.processInfo.environment["PATH"]))")
		guard let resolution = await resolveExecutablePath() else {
			logDebug("No executable found. Override executable: \(overridePath.isEmpty ? "empty" : overridePath)")
			status = .failed("CodeRabbit CLI not found. Default path is \(ReviewRunner.defaultExecutablePath()). Install it there or update the executable path in Settings.")
			return
		}
			logDebug("Using executable: \(resolution.path)")
			securityScopedExecutableURL = resolution.scopedURL
			guard let projectFolderURL = resolveProjectFolderURL() else {
				securityScopedExecutableURL?.stopAccessingSecurityScopedResource()
				securityScopedExecutableURL = nil
				status = .failed("Folder permission missing. Click Open Folder and re-select the project folder.")
				return
			}
			securityScopedProjectFolderURL = projectFolderURL

		rawOutput = ""
		findings = []
		phases = []
		status = .running
		runErrorInfo = nil
		nextAllowedRunAt = nil
		let runID = UUID()
		currentRunID = runID
		currentRunStartedAt = Date()
		completedRunID = nil

				let process = Process()
				process.executableURL = URL(fileURLWithPath: resolution.path)
				process.arguments = buildReviewArguments()
				process.currentDirectoryURL = projectFolderURL

		var environment = ProcessInfo.processInfo.environment
		environment["PATH"] = buildPortablePath(basePath: environment["PATH"])
		process.environment = environment

		let outputPipe = Pipe()
		let errorPipe = Pipe()
		process.standardOutput = outputPipe
		process.standardError = errorPipe

		outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
			guard let self else { return }
			let data = handle.availableData
			guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
			Task { @MainActor in
				self.rawOutput += chunk
				self.findings = ReviewParser.parse(from: self.rawOutput)
				self.phases = ReviewParser.parsePhases(from: self.rawOutput)
				if let errorInfo = ReviewParser.parseRunErrorInfo(from: self.rawOutput) {
					self.runErrorInfo = errorInfo
					if errorInfo.isRateLimit, let retrySeconds = errorInfo.retryAfterSeconds {
						self.nextAllowedRunAt = (errorInfo.occurredAt ?? Date()).addingTimeInterval(retrySeconds)
					}
					self.status = .failed(errorInfo.message)
				}
			}
		}

		errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
			guard let self else { return }
			let data = handle.availableData
			guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
			Task { @MainActor in
				self.rawOutput += chunk
				self.findings = ReviewParser.parse(from: self.rawOutput)
				self.phases = ReviewParser.parsePhases(from: self.rawOutput)
				if let errorInfo = ReviewParser.parseRunErrorInfo(from: self.rawOutput) {
					self.runErrorInfo = errorInfo
					if errorInfo.isRateLimit, let retrySeconds = errorInfo.retryAfterSeconds {
						self.nextAllowedRunAt = (errorInfo.occurredAt ?? Date()).addingTimeInterval(retrySeconds)
					}
					self.status = .failed(errorInfo.message)
				}
			}
		}

			let scopedExecutableURL = securityScopedExecutableURL
			let scopedProjectFolderURL = securityScopedProjectFolderURL
			process.terminationHandler = { [weak self] terminatedProcess in
				guard let self else { return }
				outputPipe.fileHandleForReading.readabilityHandler = nil
				errorPipe.fileHandleForReading.readabilityHandler = nil
				scopedExecutableURL?.stopAccessingSecurityScopedResource()
				scopedProjectFolderURL?.stopAccessingSecurityScopedResource()
				Task { @MainActor in
					self.securityScopedExecutableURL = nil
					self.securityScopedProjectFolderURL = nil
					if !self.phases.contains(.complete) {
						self.phases.append(.complete)
					}
				if case .failed = self.status {
					// Keep the parsed failure reason shown in the UI.
				} else {
					self.runErrorInfo = nil
					self.nextAllowedRunAt = nil
					self.status = .completed(terminatedProcess.terminationStatus)
				}
				self.completedRunID = runID
				self.currentRunID = nil
				self.currentRunStartedAt = nil
			}
		}

		do {
			try process.run()
			self.process = process
			} catch {
				securityScopedExecutableURL?.stopAccessingSecurityScopedResource()
				securityScopedExecutableURL = nil
				securityScopedProjectFolderURL?.stopAccessingSecurityScopedResource()
				securityScopedProjectFolderURL = nil
				status = .failed("Failed to run command: \(error.localizedDescription)")
				currentRunID = nil
				currentRunStartedAt = nil
		}
	}

	func prepareForNewReview() {
		guard currentRunID == nil else { return }
		rawOutput = ""
		findings = []
		phases = []
		runErrorInfo = nil
		completedRunID = nil
		status = .idle
	}

	func stopReviewIfNeeded() {
		guard let process, process.isRunning else { return }
		process.terminate()
		self.process = nil
	}

	private func resolveExecutablePath() async -> (path: String, scopedURL: URL?)? {
		let override = normalizedExecutablePath(executablePathOverride)
		if let override {
			var scopedURL: URL?
			if let bookmarkURL = loadSecurityScopedExecutableURL(), bookmarkURL.path == override {
				let accessed = bookmarkURL.startAccessingSecurityScopedResource()
				logDebug("Security scope access: \(accessed)")
				scopedURL = accessed ? bookmarkURL : nil
			}

			let isExecutable = FileManager.default.isExecutableFile(atPath: override)
			let exists = FileManager.default.fileExists(atPath: override)
			let isReadable = FileManager.default.isReadableFile(atPath: override)
			let isWritable = FileManager.default.isWritableFile(atPath: override)
			logDebug("Override exists: \(exists), executable: \(isExecutable), readable: \(isReadable), writable: \(isWritable)")
			if isExecutable && isReadable {
				return (override, scopedURL)
			}

			if exists && !isReadable {
				logDebug("Override exists but is not readable. This is usually a sandbox / permission issue. Pick the executable via an Open panel to grant access, or disable App Sandbox for non–Mac App Store builds.")
			}
		} else if let bookmarkURL = loadSecurityScopedExecutableURL() {
			let accessed = bookmarkURL.startAccessingSecurityScopedResource()
			logDebug("Security scope access: \(accessed)")
			let path = bookmarkURL.path
			let isExecutable = FileManager.default.isExecutableFile(atPath: path)
			let isReadable = FileManager.default.isReadableFile(atPath: path)
			if isExecutable && isReadable {
				return (path, accessed ? bookmarkURL : nil)
			}
		}

		if let fromPath = await lookupUsingWhich(binary: "coderabbit") {
			return (fromPath, nil)
		}

		let commonLocations = [
			"/usr/bin/coderabbit",
			"/Users/\(NSUserName())/.local/bin/coderabbit"
		]
		if let resolved = commonLocations.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
			return (resolved, nil)
		}
		return nil
	}

	private func lookupUsingWhich(binary: String) async -> String? {
		let portablePath = buildPortablePath(basePath: ProcessInfo.processInfo.environment["PATH"])
		return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
			DispatchQueue.global(qos: .userInitiated).async {
				let lookup = Process()
				lookup.executableURL = URL(fileURLWithPath: "/usr/bin/which")
				lookup.arguments = [binary]

				var environment = ProcessInfo.processInfo.environment
				environment["PATH"] = portablePath
				lookup.environment = environment

				let outputPipe = Pipe()
				lookup.standardOutput = outputPipe
				lookup.standardError = Pipe()

				do {
					try lookup.run()
					lookup.waitUntilExit()
					guard lookup.terminationStatus == 0 else {
						continuation.resume(returning: nil)
						return
					}
					let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
					let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
					guard let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
						continuation.resume(returning: nil)
						return
					}
					continuation.resume(returning: path)
				} catch {
					continuation.resume(returning: nil)
				}
			}
		}
	}

	private func normalizedExecutablePath(_ rawValue: String) -> String? {
		let normalized = Self.normalizeStoredExecutablePath(rawValue)
		let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }
		return trimmed
	}

	private static func normalizedUserPath(_ input: String) -> String {
		(input as NSString).expandingTildeInPath
	}

	private static func realUserHomeDirectoryPath() -> String {
		if let pwd = getpwuid(getuid()) {
			let path = String(cString: pwd.pointee.pw_dir)
			if !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				return path
			}
		}
		return "/Users/\(NSUserName())"
	}

	private static func looksLikeExecutablePath(_ input: String) -> Bool {
		let expanded = normalizedUserPath(input)
		return expanded.hasPrefix("/") && expanded.contains("/coderabbit")
	}

	private static func isForeignHomeLocalCoderabbitPath(_ path: String) -> Bool {
		let marker = "/.local/bin/coderabbit"
		guard path.hasSuffix(marker), path.hasPrefix("/Users/") else { return false }
		let currentHome = realUserHomeDirectoryPath()
		return !path.hasPrefix(currentHome + "/")
	}

	private static func remappedContainerExecutablePath(_ path: String) -> String? {
		let containerMarker = "/Library/Containers/"
		let dataMarker = "/Data/.local/bin/coderabbit"
		guard path.contains(containerMarker), path.hasSuffix(dataMarker) else { return nil }
		return defaultExecutablePath()
	}

	private func loadSecurityScopedExecutableURL() -> URL? {
		guard let data = UserDefaults.standard.data(forKey: executableBookmarkKey) else { return nil }
		var isStale = false
		guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &isStale) else {
			return nil
		}
		if isStale {
			UserDefaults.standard.removeObject(forKey: executableBookmarkKey)
			return nil
		}
		return url
	}

	private func resolveProjectFolderURL() -> URL? {
		let path = selectedFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !path.isEmpty else { return nil }

		let fallbackURL = URL(fileURLWithPath: path)
		guard let data = UserDefaults.standard.data(forKey: Self.projectFolderBookmarkKey) else {
			return FileManager.default.isReadableFile(atPath: path) ? fallbackURL : nil
		}

		var isStale = false
		guard let bookmarkedURL = try? URL(
			resolvingBookmarkData: data,
			options: [.withSecurityScope],
			bookmarkDataIsStale: &isStale
		) else {
			UserDefaults.standard.removeObject(forKey: Self.projectFolderBookmarkKey)
			return FileManager.default.isReadableFile(atPath: path) ? fallbackURL : nil
		}

		if isStale {
			UserDefaults.standard.removeObject(forKey: Self.projectFolderBookmarkKey)
			return FileManager.default.isReadableFile(atPath: path) ? fallbackURL : nil
		}

		guard bookmarkedURL.path == path else {
			return FileManager.default.isReadableFile(atPath: path) ? fallbackURL : nil
		}

		let accessed = bookmarkedURL.startAccessingSecurityScopedResource()
		logDebug("Project folder security scope access: \(accessed)")
		if accessed {
			return bookmarkedURL
		}

		return FileManager.default.isReadableFile(atPath: path) ? fallbackURL : nil
	}

	private func buildPortablePath(basePath: String?) -> String {
		let defaults = [
			"/usr/bin",
			"/bin",
			"/usr/sbin",
			"/sbin",
			"/Users/\(NSUserName())/.local/bin"
		]
		let existing = (basePath ?? "").split(separator: ":").map(String.init)
		var all = existing
		for entry in defaults where !all.contains(entry) {
			all.append(entry)
		}
		return all.joined(separator: ":")
	}

	private func splitArguments(_ input: String) -> [String] {
		var args: [String] = []
		var current = ""
		var inQuotes = false
		var quoteChar: Character = "\""

		for character in input {
			if character == "\"" || character == "'" {
				if inQuotes, character == quoteChar {
					inQuotes = false
				} else if !inQuotes {
					inQuotes = true
					quoteChar = character
				} else {
					current.append(character)
				}
				continue
			}

			if character.isWhitespace, !inQuotes {
				if !current.isEmpty {
					args.append(current)
					current.removeAll()
				}
				continue
			}

			current.append(character)
		}

		if !current.isEmpty {
			args.append(current)
		}

		return args
	}

	private func buildReviewArguments() -> [String] {
		var args = splitArguments(command)
		if !containsAnyFlag(in: args, long: "--type", short: "-t") {
			args.append(contentsOf: ["--type", normalizedReviewType(reviewType)])
		}

		let normalizedConfigFiles = configFiles
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
		if !normalizedConfigFiles.isEmpty, !containsAnyFlag(in: args, long: "--config", short: "-c") {
			args.append("--config")
			args.append(contentsOf: normalizedConfigFiles)
		}

		let normalizedBaseCommit = baseCommit.trimmingCharacters(in: .whitespacesAndNewlines)
		if !normalizedBaseCommit.isEmpty, !containsAnyFlag(in: args, long: "--base-commit") {
			args.append(contentsOf: ["--base-commit", normalizedBaseCommit])
		} else {
			let normalizedBaseBranch = baseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
			if !normalizedBaseBranch.isEmpty, !containsAnyFlag(in: args, long: "--base") {
				args.append(contentsOf: ["--base", normalizedBaseBranch])
			}
		}
		return args
	}

	private func containsAnyFlag(in args: [String], long: String, short: String? = nil) -> Bool {
		args.contains(where: {
			$0 == long
				|| (short != nil && $0 == short)
				|| $0.hasPrefix("\(long)=")
		})
	}

	private func normalizedReviewType(_ rawValue: String) -> String {
		let lowered = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		switch lowered {
		case "committed", "uncommitted":
			return lowered
		default:
			return "all"
		}
	}

	private func logDebug(_ message: String) {
		print("[ReviewRunner] \(message)")
	}

	func listGitLocalBranches(in folderPath: String) async -> [String]? {
		let trimmedPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmedPath.isEmpty else { return nil }

		return await withCheckedContinuation { (continuation: CheckedContinuation<[String]?, Never>) in
			DispatchQueue.global(qos: .userInitiated).async {
				let process = Process()
				process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
				process.arguments = ["for-each-ref", "--format=%(refname:short)", "refs/heads"]
				process.currentDirectoryURL = URL(fileURLWithPath: trimmedPath)

				let outputPipe = Pipe()
				process.standardOutput = outputPipe
				process.standardError = Pipe()

				do {
					try process.run()
					process.waitUntilExit()
					guard process.terminationStatus == 0 else {
						continuation.resume(returning: nil)
						return
					}

					let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
					guard let output = String(data: outputData, encoding: .utf8) else {
						continuation.resume(returning: nil)
						return
					}

					let branches = output
						.split(whereSeparator: \.isNewline)
						.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
						.filter { !$0.isEmpty }

					if branches.isEmpty {
						continuation.resume(returning: nil)
						return
					}

					let uniqueBranches = Array(Set(branches)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
					continuation.resume(returning: uniqueBranches)
				} catch {
					continuation.resume(returning: nil)
				}
			}
		}
	}
}
