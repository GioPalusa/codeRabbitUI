import AppKit
import SwiftUI

struct SettingsView: View {
	@EnvironmentObject private var historyStore: ReviewHistoryStore
	@AppStorage("coderabbitExecutablePath") private var coderabbitExecutablePath: String = ReviewRunner.defaultExecutablePath()
	@AppStorage("reviewConfigFilesJSON") private var reviewConfigFilesJSON: String = "[]"
	@State private var showClearHistoryConfirmation = false
	@State private var reviewConfigFiles: [String] = []
	@State private var cliLookupStatus: String?
	private let executableBookmarkKey = "coderabbitExecutableBookmark"
	private let installCommand = "curl -fsSL https://cli.coderabbit.ai/install.sh | sh"

	var body: some View {
		VStack(spacing: 12) {
			Form {
				Section("CodeRabbit CLI") {
					TextField("Executable path", text: $coderabbitExecutablePath)
					HStack {
						Button("Detect Installed CLI") {
							detectInstalledCLIPath()
						}
						Button("Reset to Default") {
							coderabbitExecutablePath = ReviewRunner.defaultExecutablePath()
						}
					}
					if let cliLookupStatus {
						Text(cliLookupStatus)
							.font(.caption)
							.foregroundStyle(.secondary)
							.padding(.bottom)
					}

					Text("Default is \(ReviewRunner.defaultExecutablePath()). If you installed it elsewhere, update the path here.")
						.font(.caption)
						.foregroundStyle(.secondary)
					HStack(spacing: 10) {
						Text("Install with:")
							.font(.caption)
							.foregroundStyle(.secondary)
						Text(installCommand)
							.font(.system(.caption, design: .monospaced))
							.lineLimit(1)
							.textSelection(.enabled)
						Button("Copy") {
							copyInstallCommand()
						}
						.buttonStyle(.bordered)
						.controlSize(.small)
					}
					.padding(.bottom)
				}

				Section("Additional Instructions") {
					if reviewConfigFiles.isEmpty {
						Text("No instruction files selected.")
							.font(.caption)
							.foregroundStyle(.secondary)
					} else {
						ForEach(reviewConfigFiles, id: \.self) { filePath in
							HStack(spacing: 8) {
								Text(URL(fileURLWithPath: filePath).lastPathComponent)
									.lineLimit(1)
								Spacer()
								Button("Remove") {
									removeConfigFile(filePath)
								}
								.buttonStyle(.bordered)
								.controlSize(.small)
							}
							Text(filePath)
								.font(.caption2)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
						.padding(.bottom)
					}

					Button("Add Instruction File(s)…") {
						pickConfigFiles()
					}
					.buttonStyle(.bordered)
					.padding(.bottom)
				}

				Section("Review History") {
					Text("Stored reviews are kept for 30 days.")
						.font(.caption)
						.foregroundStyle(.secondary)
					Button("Clear Stored Reviews") {
						showClearHistoryConfirmation = true
					}
					.foregroundStyle(.red)
					.padding(.bottom)
				}
			}

			Divider()

			VStack {
				Text("This app is an independent client for the CodeRabbit CLI. \nIt is not affiliated with, endorsed by, or maintained by CodeRabbit, Inc. or CodeRabbit AI.")
					.font(.caption)
					.fixedSize(horizontal: false, vertical: true)
				Image("PalusaLogo")
					.resizable()
					.scaledToFit()
					.frame(height: 45)
				Text("Made with 🤖 and ♥️ by Palusa")
					.font(.caption)
					.foregroundStyle(.secondary)

				if let palusaURL = URL(string: "https://www.palusa.se") {
					Link("palusa.se", destination: palusaURL)
						.font(.caption.weight(.semibold))
				}
			}
		}
		.padding(20)
		.frame(width: 650)
		.alert("Clear all stored reviews?", isPresented: $showClearHistoryConfirmation) {
			Button("Cancel", role: .cancel) {}
			Button("Clear", role: .destructive) {
				historyStore.clearAll()
			}
		} message: {
			Text("This removes all saved review posts from local history.")
		}
		.onAppear {
			coderabbitExecutablePath = ReviewRunner.normalizeStoredExecutablePath(coderabbitExecutablePath)
			loadReviewConfigFiles()
		}
	}

	private func detectInstalledCLIPath() {
		Task {
			let detectedPath = await findCoderabbitPathWithWhich()
			await MainActor.run {
				if let detectedPath {
					coderabbitExecutablePath = detectedPath
					cliLookupStatus = "Found CodeRabbit CLI at: \(detectedPath)"
				} else {
					cliLookupStatus = "CodeRabbit CLI not found on PATH. Install it and retry detection."
				}
			}
		}
	}

	private func findCoderabbitPathWithWhich() async -> String? {
		let defaultPath = ReviewRunner.defaultExecutablePath()
		if FileManager.default.isExecutableFile(atPath: defaultPath) {
			return defaultPath
		}

		let commonPaths = [
			"/usr/bin/coderabbit",
			"/opt/homebrew/bin/coderabbit",
			"/usr/local/bin/coderabbit",
		]
		if let resolved = commonPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
			return resolved
		}

		return await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				let process = Process()
				process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
				process.arguments = ["coderabbit"]
				var environment = ProcessInfo.processInfo.environment
				environment["PATH"] = buildPortablePath(basePath: environment["PATH"])
				process.environment = environment
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
					let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
					let path = String(data: data, encoding: .utf8)?
						.trimmingCharacters(in: .whitespacesAndNewlines)
					guard let path, !path.isEmpty else {
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

	private func buildPortablePath(basePath: String?) -> String {
		let defaults = [
			"/usr/bin",
			"/bin",
			"/usr/sbin",
			"/sbin",
			"/opt/homebrew/bin",
			"/usr/local/bin",
			FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
		]
		let existing = (basePath ?? "").split(separator: ":").map(String.init)
		var all = existing
		for entry in defaults where !all.contains(entry) {
			all.append(entry)
		}
		return all.joined(separator: ":")
	}

	private func copyInstallCommand() {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(installCommand, forType: .string)
		cliLookupStatus = "Install command copied."
	}

	private func pickConfigFiles() {
		let panel = NSOpenPanel()
		panel.canChooseFiles = true
		panel.canChooseDirectories = false
		panel.allowsMultipleSelection = true
		panel.prompt = "Add"
		if panel.runModal() == .OK {
			let paths = panel.urls.map(\.path)
			addConfigFiles(paths)
		}
	}

	private func addConfigFiles(_ filePaths: [String]) {
		var updated = reviewConfigFiles
		for path in filePaths {
			let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmed.isEmpty else { continue }
			if !updated.contains(trimmed) {
				updated.append(trimmed)
			}
		}
		reviewConfigFiles = updated
		saveReviewConfigFiles()
	}

	private func removeConfigFile(_ filePath: String) {
		reviewConfigFiles.removeAll { $0 == filePath }
		saveReviewConfigFiles()
	}

	private func loadReviewConfigFiles() {
		guard let data = reviewConfigFilesJSON.data(using: .utf8) else {
			reviewConfigFiles = []
			return
		}
		let decoded = (try? JSONDecoder().decode([String].self, from: data)) ?? []
		reviewConfigFiles = decoded.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
	}

	private func saveReviewConfigFiles() {
		guard let data = try? JSONEncoder().encode(reviewConfigFiles),
			  let encoded = String(data: data, encoding: .utf8)
		else { return }
		reviewConfigFilesJSON = encoded
	}
}
