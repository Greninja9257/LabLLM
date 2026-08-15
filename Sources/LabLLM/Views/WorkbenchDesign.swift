import SwiftUI

enum WorkbenchTheme {
    static var accent: Color {
        let raw = UserDefaults.standard.string(forKey: "labllm.accent") ?? Preferences.Accent.blue.rawValue
        return (Preferences.Accent(rawValue: raw) ?? .blue).color
    }
    static let ink = Color.primary
    static let muted = Color.secondary
    static var panelOpacity: Double {
        let stored = UserDefaults.standard.object(forKey: "labllm.panelOpacity") as? Double
        return min(max(stored ?? 0.72, 0.35), 1.0)
    }
    static var cornerRadius: CGFloat {
        let stored = UserDefaults.standard.object(forKey: "labllm.cornerRadius") as? Double
        return CGFloat(min(max(stored ?? 8, 2), 18))
    }
    static var panel: Color { Color(nsColor: .controlBackgroundColor).opacity(panelOpacity) }
    static let elevatedPanel = Color(nsColor: .windowBackgroundColor).opacity(0.92)
    static let grid = Color.primary.opacity(0.07)
    static let success = Color(red: 0.15, green: 0.64, blue: 0.42)
    static var validation: Color {
        let raw = UserDefaults.standard.string(forKey: "labllm.validationColor") ?? Preferences.ValidationColor.orange.rawValue
        return (Preferences.ValidationColor(rawValue: raw) ?? .orange).color
    }
}

struct WorkbenchPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(isEnabled ? WorkbenchTheme.accent.opacity(configuration.isPressed ? 0.76 : 1) : Color.secondary.opacity(0.28), in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct WorkbenchSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(isEnabled ? WorkbenchTheme.ink : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? WorkbenchTheme.accent.opacity(0.14) : WorkbenchTheme.elevatedPanel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous).strokeBorder(isEnabled ? WorkbenchTheme.grid.opacity(2) : WorkbenchTheme.grid) }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct WorkbenchGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WorkbenchTheme.ink)
            configuration.content
        }
        .padding(WorkbenchTheme.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchTheme.panel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                .strokeBorder(WorkbenchTheme.grid, lineWidth: 1)
        }
    }
}

extension WorkbenchTheme {
    static var density: Preferences.Density {
        let raw = UserDefaults.standard.string(forKey: "labllm.density") ?? Preferences.Density.comfortable.rawValue
        return Preferences.Density(rawValue: raw) ?? .comfortable
    }
    static var pagePadding: CGFloat { density.pagePadding }
    static var panelPadding: CGFloat { density.panelPadding }
}

struct WorkbenchPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(WorkbenchTheme.accent, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WorkbenchTheme.accent)
                Text(title).font(.system(size: 28, weight: .bold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct WorkbenchMetric: View {
    let label: String
    let value: String
    var tone: Color = .primary
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.caption).foregroundStyle(tone)
            }
            Text(value).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone)
            Text(label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(WorkbenchTheme.elevatedPanel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous).strokeBorder(WorkbenchTheme.grid) }
    }
}

struct WorkbenchPill: View {
    let text: String
    var color: Color = WorkbenchTheme.accent
    var body: some View {
        Text(text).font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct WorkbenchEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(WorkbenchTheme.accent)
            Text(title).font(.title3.bold())
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(WorkbenchTheme.panel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
    }
}

struct WorkbenchSearchBar: View {
    @Binding var query: String
    let prompt: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $query).textFieldStyle(.plain).onSubmit(action)
            Button(action: action) {
                Image(systemName: "arrow.right").font(.caption.weight(.bold)).frame(width: 24, height: 24)
                    .background(WorkbenchTheme.accent, in: RoundedRectangle(cornerRadius: max(4, WorkbenchTheme.cornerRadius - 2), style: .continuous)).foregroundStyle(.white)
            }.buttonStyle(.plain).help("Search")
        }
        .padding(7)
        .background(WorkbenchTheme.elevatedPanel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous).strokeBorder(WorkbenchTheme.grid) }
    }
}
