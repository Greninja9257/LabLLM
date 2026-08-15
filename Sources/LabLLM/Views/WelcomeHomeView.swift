import SwiftUI

struct WelcomeHomeView: View {
    @EnvironmentObject var prefs: Preferences

    private let primaryActions: [(String, String, String, NavSection)] = [
        ("Design model", "Choose an architecture and scale.", "cube.transparent", .model),
        ("Pre-training data", "Import a corpus and prepare text.", "text.book.closed", .dataset),
        ("Fine-tuning data", "Bring in conversations and instructions.", "tray.full", .fineTuneData),
        ("Models", "Continue, inspect, or quantize a checkpoint.", "cube.box", .checkpoints)
    ]

    var body: some View {
        ZStack {
            if prefs.showWelcomeAnimation {
                ParticleLifeBackdrop().ignoresSafeArea()
            } else {
                LinearGradient(colors: [Color(red: 0.08, green: 0.15, blue: 0.22), Color(red: 0.12, green: 0.20, blue: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    statusBand
                    actions
                    resumeBand
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(.horizontal, WorkbenchTheme.pagePadding + 18)
                .padding(.vertical, WorkbenchTheme.pagePadding + 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(WorkbenchTheme.accent, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text("LABLLM STUDIO").font(.caption.weight(.bold)).foregroundStyle(WorkbenchTheme.accent)
                Text("Start a local language-model run.").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                Text("Design a model, bring in data, and train on this Mac.").font(.callout).foregroundStyle(.white.opacity(0.68))
            }
            Spacer()
        }
    }

    private var statusBand: some View {
        HStack(spacing: 0) {
            status("Mode", value: prefs.mode.label, icon: prefs.mode.icon, color: WorkbenchTheme.accent)
            Divider().frame(height: 44)
            status("Storage", value: "Local", icon: "internaldrive", color: Color(red: 0.16, green: 0.55, blue: 0.45))
            Divider().frame(height: 44)
            status("Privacy", value: "Offline-ready", icon: "lock.shield", color: Color(red: 0.75, green: 0.42, blue: 0.18))
        }
        .padding(.vertical, 14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.16)).frame(height: 1) }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start here").font(.headline).foregroundStyle(.white)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(Array(primaryActions.enumerated()), id: \.element.0) { index, action in
                    actionButton(action, number: index + 1)
                }
            }
        }
    }

    private var resumeBand: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Continue your work").font(.headline).foregroundStyle(.white)
                Text("Open Training to run a configured model, or Sampling to work with a model already in memory.")
                    .font(.callout).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            compactAction("Training", icon: "waveform.path.ecg", section: .training)
            compactAction("Sampling", icon: "text.cursor", section: .sampling)
        }
        .padding(.top, 8)
    }

    private func actionButton(_ action: (String, String, String, NavSection), number: Int) -> some View {
        Button { navigate(action.3) } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: action.2)
                        .foregroundStyle(action.3.iconColor)
                        .font(.title2.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(action.3.iconColor.opacity(0.16), in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
                    Spacer()
                    Text(String(format: "%02d", number))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white.opacity(0.34))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(action.0).font(.headline).foregroundStyle(.white)
                    Text(action.1).font(.caption).foregroundStyle(.white.opacity(0.63)).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text("Open workspace").font(.caption.weight(.semibold)).foregroundStyle(action.3.iconColor)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(action.3.iconColor)
                }
            }
            .padding(WorkbenchTheme.panelPadding)
            .frame(maxWidth: .infinity, minHeight: 164, alignment: .leading)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
            .overlay(alignment: .leading) { Rectangle().fill(action.3.iconColor).frame(width: 3) }
            .overlay { RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(StudioTileButtonStyle())
    }

    private func compactAction(_ title: String, icon: String, section: NavSection) -> some View {
        Button { navigate(section) } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.caption.weight(.bold))
                Text(title).font(.caption.weight(.semibold))
                Image(systemName: "arrow.right").font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(section.iconColor.opacity(0.22), in: Capsule())
            .overlay { Capsule().strokeBorder(section.iconColor.opacity(0.62)) }
        }
        .buttonStyle(.plain)
    }

    private func status(_ title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.callout.weight(.semibold)).foregroundStyle(.white)
                Text(title).font(.caption2).foregroundStyle(.white.opacity(0.58))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private func navigate(_ section: NavSection) {
        NotificationCenter.default.post(name: .navigateToSection, object: section.rawValue)
    }
}

private struct StudioTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? 0.07 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
