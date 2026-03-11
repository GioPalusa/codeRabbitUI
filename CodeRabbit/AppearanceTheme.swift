import SwiftUI

enum AppearanceTheme: String, CaseIterable, Identifiable {
	case system
	case light
	case dark

	var id: String { rawValue }

	var label: String {
		switch self {
		case .system: return "System"
		case .light: return "Light"
		case .dark: return "Dark"
		}
	}

	var colorScheme: ColorScheme? {
		switch self {
		case .system: return nil
		case .light: return .light
		case .dark: return .dark
		}
	}

	static func normalized(_ value: String) -> AppearanceTheme {
		AppearanceTheme(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .system
	}
}
