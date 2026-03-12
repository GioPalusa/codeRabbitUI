import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var historyStore: ReviewHistoryStore
    @AppStorage("coderabbitExecutablePath") private var coderabbitExecutablePath: String = ReviewRunner.defaultExecutablePath()
    @AppStorage("reviewConfigFilesJSON") private var reviewConfigFilesJSON: String = "[]"
    @AppStorage("selectedProjectFolderPath") private var selectedProjectFolderPath: String = ""
    @AppStorage("recentProjectFoldersJSON") private var recentProjectFoldersJSON: String = "[]"
    @AppStorage("appAppearanceTheme") private var appAppearanceTheme: String = AppearanceTheme.system.rawValue
    @AppStorage("appAutoCheckForUpdates") private var appAutoCheckForUpdates: Bool = true
    @State private var showClearHistoryConfirmation = false
    @State private var showClearProjectFoldersConfirmation = false
    @State private var reviewConfigFiles: [String] = []
    @State private var cliLookupStatus: String?
    @State private var appUpdateInfo: AppUpdateInfo?
    @State private var appUpdateStatusMessage: String?
    @State private var isCheckingForAppUpdate = false
    private let executableBookmarkKey = "coderabbitExecutableBookmark"
    private let projectFolderBookmarkKey = ReviewRunner.projectFolderBookmarkKey
    private let installCommand = "curl -fsSL https://cli.coderabbit.ai/install.sh | sh"

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Form {
                    Section("Executable Path") {
                        TextField("", text: $coderabbitExecutablePath)
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

                    Divider()

                    Section("Additional Instructions") {
                        if reviewConfigFiles.isEmpty {
                            Text("No instruction files selected. \nAdditional instructions are files you can use with CodeRabbit AI (e.g.,claude.md, coderabbit.yaml)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
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

                    Section("Appearance") {
                        Text("Color Theme")
                        Picker("", selection: $appAppearanceTheme) {
                            ForEach(AppearanceTheme.allCases) { theme in
                                Text(theme.label).tag(theme.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Choose how CodeRabbit should appear. Default is System.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom)
                    }

                    Section("App Updates") {
                        Text("Current version: \(AppUpdateService.currentInstalledVersionLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Check for updates automatically", isOn: $appAutoCheckForUpdates)

                        HStack(spacing: 10) {
                            Button(isCheckingForAppUpdate ? "Checking..." : "Check for Updates") {
                                checkForAppUpdate()
                            }
                            .disabled(isCheckingForAppUpdate)

                            if let appUpdateInfo {
                                Button("Download Latest") {
                                    let destination = appUpdateInfo.directDownloadURL ?? appUpdateInfo.releaseURL
                                    NSWorkspace.shared.open(destination)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Release Notes") {
                                    NSWorkspace.shared.open(appUpdateInfo.releaseURL)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if let appUpdateStatusMessage {
                            Text(appUpdateStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.bottom)
                        }
                    }

                    HStack {
                        VStack(alignment: .leading) {
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

                        Spacer()

                        VStack(alignment: .leading) {
                            Section("Project Folders") {
                                Text("Clears the recent folder list and selected workspace.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Clear Project Folder List") {
                                    showClearProjectFoldersConfirmation = true
                                }
                                .foregroundStyle(.red)
                                .padding(.bottom)
                            }
                        }
                    }
                    .padding(.top)
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

                    HStack {
                        if let palusaURL = URL(string: "https://www.palusa.se") {
                            Link("palusa.se", destination: palusaURL)
                                .font(.caption.weight(.semibold))
                                .padding(.trailing)
                        }
                        if let projectURL = URL(string: "https://github.com/GioPalusa/codeRabbitUI/") {
                            Link("Project on GitHub", destination: projectURL)
                                .font(.caption.weight(.semibold))
                        }
                    }
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
        .alert("Clear saved project folders?", isPresented: $showClearProjectFoldersConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearSavedProjectFolders()
            }
        } message: {
            Text("This removes the recent project folder list and current selection.")
        }
        .onAppear {
            coderabbitExecutablePath = ReviewRunner.normalizeStoredExecutablePath(coderabbitExecutablePath)
            appAppearanceTheme = AppearanceTheme.normalized(appAppearanceTheme).rawValue
            loadReviewConfigFiles()
        }
        .onChange(of: appAppearanceTheme) { _, newValue in
            appAppearanceTheme = AppearanceTheme.normalized(newValue).rawValue
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

    private func checkForAppUpdate() {
        Task {
            await MainActor.run {
                isCheckingForAppUpdate = true
                appUpdateStatusMessage = "Checking for updates..."
            }

            let result = await AppUpdateService.checkForUpdates()
            await MainActor.run {
                isCheckingForAppUpdate = false
                switch result {
                case let .updateAvailable(updateInfo):
                    appUpdateInfo = updateInfo
                    appUpdateStatusMessage = "New version \(updateInfo.latestVersion) available (installed \(updateInfo.currentVersion))."
                case let .upToDate(currentVersion, _):
                    appUpdateInfo = nil
                    appUpdateStatusMessage = "You're up to date (\(currentVersion))."
                case let .failed(message):
                    appUpdateInfo = nil
                    appUpdateStatusMessage = message
                }
            }
        }
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

    private func clearSavedProjectFolders() {
        recentProjectFoldersJSON = "[]"
        selectedProjectFolderPath = ""
        UserDefaults.standard.removeObject(forKey: projectFolderBookmarkKey)
    }
}
