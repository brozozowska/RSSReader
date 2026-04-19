import SwiftUI

enum AppThemeVariant: String, Equatable, Sendable {
    case light
    case dark
    case black

    var primaryBackground: Color {
        switch self {
        case .light:
            Color.white
        case .dark:
            Color(red: 0.13, green: 0.13, blue: 0.15)
        case .black:
            Color.black
        }
    }

    var secondaryBackground: Color {
        switch self {
        case .light:
            Color(uiColor: .systemGray6)
        case .dark:
            Color(red: 0.18, green: 0.18, blue: 0.20)
        case .black:
            Color(red: 0.07, green: 0.07, blue: 0.08)
        }
    }

    var tertiaryBackground: Color {
        switch self {
        case .light:
            Color(uiColor: .systemGray5)
        case .dark:
            Color(red: 0.24, green: 0.24, blue: 0.27)
        case .black:
            Color(red: 0.12, green: 0.12, blue: 0.13)
        }
    }

    var previewGradientColors: [Color] {
        switch self {
        case .light:
            [Color.white, Color(uiColor: .systemGray6)]
        case .dark:
            [Color(red: 0.16, green: 0.16, blue: 0.18), Color(red: 0.11, green: 0.11, blue: 0.13)]
        case .black:
            [Color.black, Color(red: 0.05, green: 0.05, blue: 0.06)]
        }
    }
}

struct AppThemeApplicationPolicy {
    let interfaceThemeMode: InterfaceThemeMode
    let systemColorScheme: ColorScheme

    var preferredColorScheme: ColorScheme? {
        switch interfaceThemeMode {
        case .automaticLightDark, .automaticLightBlack:
            nil
        case .light:
            .light
        case .dark, .black:
            .dark
        }
    }

    var resolvedTheme: AppThemeVariant {
        switch interfaceThemeMode {
        case .automaticLightDark:
            systemColorScheme == .dark ? .dark : .light
        case .automaticLightBlack:
            systemColorScheme == .dark ? .black : .light
        case .light:
            .light
        case .dark:
            .dark
        case .black:
            .black
        @unknown default:
            .light
        }
    }
}

private struct AppThemeVariantKey: EnvironmentKey {
    static let defaultValue: AppThemeVariant = .light
}

extension EnvironmentValues {
    var appThemeVariant: AppThemeVariant {
        get { self[AppThemeVariantKey.self] }
        set { self[AppThemeVariantKey.self] = newValue }
    }
}
