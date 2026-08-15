import Foundation
import SwiftUI

/// Simple / Advanced / Expert modes. Simple hides advanced controls and shows
/// more guidance + presets; Expert exposes everything with minimal hand-holding.
enum AppMode: String, Codable, CaseIterable, Identifiable {
    case simple, advanced, expert
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var blurb: String {
        switch self {
        case .simple:   return "Guided. The full learning path with sensible defaults."
        case .advanced: return "Adds useful controls for tuning and experiments."
        case .expert:   return "Everything exposed. Minimal hand-holding."
        }
    }
    var icon: String {
        switch self {
        case .simple: return "leaf"
        case .advanced: return "slider.horizontal.3"
        case .expert: return "wand.and.stars"
        }
    }
    /// Rank for feature gating (higher unlocks more).
    var rank: Int { self == .simple ? 0 : (self == .advanced ? 1 : 2) }
}

/// Persisted user preferences (native UserDefaults — the correct store for a real
/// macOS app; this is not a sandboxed web artifact).
final class Preferences: ObservableObject {
    @AppStorage("labllm.mode") private var modeRaw: String = AppMode.simple.rawValue
    @AppStorage("labllm.hasOnboarded") var hasOnboarded: Bool = false
    @AppStorage("labllm.showTips") var showTips: Bool = true
    @AppStorage("labllm.appearance") private var appearanceRaw: String = "system"
    @AppStorage("labllm.accent") private var accentRaw: String = Accent.blue.rawValue
    @AppStorage("labllm.validationColor") private var validationRaw: String = ValidationColor.orange.rawValue
    @AppStorage("labllm.density") private var densityRaw: String = Density.comfortable.rawValue
    @AppStorage("labllm.cornerRadius") var cornerRadius: Double = 8
    @AppStorage("labllm.panelOpacity") var panelOpacity: Double = 0.72
    @AppStorage("labllm.sidebarWidth") var sidebarWidth: Double = 240
    @AppStorage("labllm.showWelcomeAnimation") var showWelcomeAnimation: Bool = true
    @AppStorage("labllm.respectModeFeatureGates") var respectModeFeatureGates: Bool = true
    @AppStorage("labllm.showSidebarGroups") var showSidebarGroups: Bool = true
    @AppStorage("labllm.showTrainingStatusBadge") var showTrainingStatusBadge: Bool = true
    @AppStorage("labllm.showDatasetHints") var showDatasetHints: Bool = true
    @AppStorage("labllm.autoShowWelcome") var autoShowWelcome: Bool = true
    @AppStorage("labllm.hiddenNavigationSections") private var hiddenNavigationSectionsRaw: String = ""

    var mode: AppMode {
        get { AppMode(rawValue: modeRaw) ?? .simple }
        set { modeRaw = newValue.rawValue; objectWillChange.send() }
    }

    var appearance: Appearance {
        get { Appearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue; objectWillChange.send() }
    }

    var accent: Accent {
        get { Accent(rawValue: accentRaw) ?? .blue }
        set { accentRaw = newValue.rawValue; objectWillChange.send() }
    }

    var validationColor: ValidationColor {
        get { ValidationColor(rawValue: validationRaw) ?? .orange }
        set { validationRaw = newValue.rawValue; objectWillChange.send() }
    }

    var density: Density {
        get { Density(rawValue: densityRaw) ?? .comfortable }
        set { densityRaw = newValue.rawValue; objectWillChange.send() }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var colorScheme: ColorScheme? {
            switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
        }
    }

    enum Accent: String, CaseIterable, Identifiable {
        case blue, teal, green, pink, purple, graphite
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var color: Color {
            switch self {
            case .blue: return Color(red: 0.20, green: 0.47, blue: 0.98)
            case .teal: return Color(red: 0.10, green: 0.62, blue: 0.68)
            case .green: return Color(red: 0.15, green: 0.64, blue: 0.42)
            case .pink: return Color(red: 0.91, green: 0.36, blue: 0.54)
            case .purple: return Color(red: 0.55, green: 0.38, blue: 0.90)
            case .graphite: return Color(red: 0.38, green: 0.42, blue: 0.48)
            }
        }
    }

    enum ValidationColor: String, CaseIterable, Identifiable {
        case orange, amber, red, violet
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var color: Color {
            switch self {
            case .orange: return .orange
            case .amber: return Color(red: 0.92, green: 0.68, blue: 0.18)
            case .red: return Color(red: 0.88, green: 0.24, blue: 0.20)
            case .violet: return Color(red: 0.60, green: 0.42, blue: 0.92)
            }
        }
    }

    enum Density: String, CaseIterable, Identifiable {
        case compact, comfortable, spacious
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var pagePadding: CGFloat {
            switch self { case .compact: return 16; case .comfortable: return 24; case .spacious: return 32 }
        }
        var panelPadding: CGFloat {
            switch self { case .compact: return 12; case .comfortable: return 18; case .spacious: return 24 }
        }
    }

    func resetOnboarding() { hasOnboarded = false }

    func isNavigationSectionVisible(_ id: String) -> Bool {
        !hiddenNavigationSectionIDs.contains(id)
    }

    func setNavigationSection(_ id: String, visible: Bool) {
        var ids = hiddenNavigationSectionIDs
        if visible { ids.remove(id) } else { ids.insert(id) }
        hiddenNavigationSectionsRaw = ids.sorted().joined(separator: ",")
        objectWillChange.send()
    }

    func resetFeatureVisibility() {
        hiddenNavigationSectionsRaw = ""
        respectModeFeatureGates = true
        showSidebarGroups = true
        showTrainingStatusBadge = true
        showDatasetHints = true
        autoShowWelcome = true
        objectWillChange.send()
    }

    func resetCustomization() {
        appearance = .system
        accent = .blue
        validationColor = .orange
        density = .comfortable
        cornerRadius = 8
        panelOpacity = 0.72
        sidebarWidth = 240
        showWelcomeAnimation = true
        showTips = true
        resetFeatureVisibility()
        objectWillChange.send()
    }

    /// Whether a feature at `required` mode should be visible in the current mode.
    func unlocked(_ required: AppMode) -> Bool { mode.rank >= required.rank }

    private var hiddenNavigationSectionIDs: Set<String> {
        Set(hiddenNavigationSectionsRaw.split(separator: ",").map(String.init))
    }
}
