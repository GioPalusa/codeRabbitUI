//
//  CodeRabbitApp.swift
//  CodeRabbit
//
//  Created by Giovanni Palusa on 2026-03-03.
//

import SwiftUI

@main
struct CodeRabbitApp: App {
	@StateObject private var historyStore = ReviewHistoryStore()

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environmentObject(historyStore)
		}
		Settings {
			SettingsView()
				.environmentObject(historyStore)
		}
	}
}
