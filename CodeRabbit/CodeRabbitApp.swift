//
//  CodeRabbitApp.swift
//  CodeRabbit
//
//  Created by Giovanni Palusa on 2026-03-03.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class SystemAppearanceObserver: ObservableObject {
    @Published private(set) var colorScheme: ColorScheme = .light

    init() {
        updateColorScheme()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSystemAppearanceChange),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc
    private func handleSystemAppearanceChange() {
        updateColorScheme()
    }

    private func updateColorScheme() {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        colorScheme = match == .darkAqua ? .dark : .light
    }
}

@main
struct CodeRabbitApp: App {
    @StateObject private var historyStore = ReviewHistoryStore()
    @StateObject private var appearanceObserver = SystemAppearanceObserver()
    @AppStorage("appAppearanceTheme") private var appAppearanceTheme: String = AppearanceTheme.system.rawValue

    private var selectedAppearanceTheme: AppearanceTheme {
        AppearanceTheme.normalized(appAppearanceTheme)
    }

    private var resolvedColorScheme: ColorScheme {
        switch selectedAppearanceTheme {
        case .system:
            return appearanceObserver.colorScheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id("main-\(appAppearanceTheme)")
                .environmentObject(historyStore)
                .preferredColorScheme(resolvedColorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        Settings {
            SettingsView()
                .id("settings-\(appAppearanceTheme)")
                .environmentObject(historyStore)
                .preferredColorScheme(resolvedColorScheme)
        }
    }
}
