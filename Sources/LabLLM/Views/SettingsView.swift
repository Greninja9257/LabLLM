import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var state: AppState
    @EnvironmentObject var tutorial: TutorialState
    var showTutorial: () -> Void
    var showWelcome: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkbenchPageHeader(eyebrow: "System", title: "Settings", subtitle: "Control how LabLLM presents itself and guides your work.", icon: "gearshape")

                GroupBox("Mode") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(AppMode.allCases) { mode in
                            let tutorialAction = tutorial.modeAction(for: mode)
                            Button {
                                prefs.mode = mode
                                if let tutorialAction { tutorial.complete(tutorialAction) }
                            } label: {
                                HStack {
                                    Image(systemName: mode.icon).frame(width: 26)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(mode.label).font(.headline)
                                        Text(mode.blurb).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: prefs.mode == mode ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(prefs.mode == mode ? Color.accentColor : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .tutorialTarget(tutorialAction ?? .idle)
                        }
                    }.padding(8)
                }

                GroupBox("Appearance") {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Theme", selection: Binding(get: { prefs.appearance }, set: { prefs.appearance = $0 })) {
                            ForEach(Preferences.Appearance.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Accent").font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(Preferences.Accent.allCases) { accent in
                                    Button {
                                        prefs.accent = accent
                                    } label: {
                                        Circle()
                                            .fill(accent.color)
                                            .frame(width: 26, height: 26)
                                            .overlay {
                                                if prefs.accent == accent {
                                                    Image(systemName: "checkmark")
                                                        .font(.caption.bold())
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .help(accent.label)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Validation loss color").font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(Preferences.ValidationColor.allCases) { color in
                                    Button {
                                        prefs.validationColor = color
                                    } label: {
                                        RoundedRectangle(cornerRadius: max(4, WorkbenchTheme.cornerRadius - 2), style: .continuous)
                                            .fill(color.color)
                                            .frame(width: 34, height: 22)
                                            .overlay {
                                                if prefs.validationColor == color {
                                                    Image(systemName: "checkmark")
                                                        .font(.caption.bold())
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .help(color.label)
                                }
                            }
                        }
                    }.padding(8)
                }

                GroupBox("Guidance") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show inline tips", isOn: Binding(get: { prefs.showTips }, set: { prefs.showTips = $0 }))
                        Toggle("Show animated welcome background", isOn: Binding(get: { prefs.showWelcomeAnimation }, set: { prefs.showWelcomeAnimation = $0 }))
                        Toggle("Show welcome automatically on first launch", isOn: Binding(get: { prefs.autoShowWelcome }, set: { prefs.autoShowWelcome = $0 }))
                        HStack {
                            Button("Replay tutorial") { showTutorial() }
                            Button("Show welcome screen") { showWelcome() }
                        }
                    }.padding(8)
                }

                GroupBox("Features") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Use Simple / Advanced / Expert feature gates", isOn: Binding(get: { prefs.respectModeFeatureGates }, set: { prefs.respectModeFeatureGates = $0 }))
                        Toggle("Show sidebar section headers", isOn: Binding(get: { prefs.showSidebarGroups }, set: { prefs.showSidebarGroups = $0 }))
                        Toggle("Show training status badge", isOn: Binding(get: { prefs.showTrainingStatusBadge }, set: { prefs.showTrainingStatusBadge = $0 }))
                        Toggle("Show dataset browser hints", isOn: Binding(get: { prefs.showDatasetHints }, set: { prefs.showDatasetHints = $0 }))

                        Divider()

                        Text("Visible pages").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                            ForEach(NavSection.allCases) { section in
                                featureButton(section)
                            }
                        }

                        Button("Reset feature visibility") { prefs.resetFeatureVisibility() }
                            .buttonStyle(WorkbenchSecondaryButtonStyle())
                    }.padding(8)
                }

                GroupBox("Layout") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Density", selection: Binding(get: { prefs.density }, set: { prefs.density = $0 })) {
                            ForEach(Preferences.Density.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        slider("Corner radius", value: Binding(get: { prefs.cornerRadius }, set: { prefs.cornerRadius = $0 }), range: 2...18, suffix: "px")
                        slider("Panel opacity", value: Binding(get: { prefs.panelOpacity }, set: { prefs.panelOpacity = $0 }), range: 0.35...1.0, suffix: "")
                        slider("Sidebar width", value: Binding(get: { prefs.sidebarWidth }, set: { prefs.sidebarWidth = $0 }), range: 200...320, suffix: "px")

                        Button("Reset customization") { prefs.resetCustomization() }
                            .buttonStyle(WorkbenchSecondaryButtonStyle())
                    }.padding(8)
                }

                GroupBox("About") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LabLLM — local GPT training on Apple MLX.").font(.callout)
                        Text("Chip: \(state.hardware.chip) · \(String(format: "%.0f GB", state.hardware.physicalMemoryGB)) unified memory")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
            }
            .padding(WorkbenchTheme.pagePadding)
        }
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack {
            Text(label).frame(width: 130, alignment: .leading)
            Slider(value: value, in: range)
            Text(formatted(value.wrappedValue, suffix: suffix))
                .font(.caption.monospacedDigit())
                .frame(width: 58, alignment: .trailing)
        }
    }

    private func featureButton(_ section: NavSection) -> some View {
        let visible = section == .settings || prefs.isNavigationSectionVisible(section.rawValue)
        let gated = prefs.respectModeFeatureGates && !prefs.unlocked(section.minMode)
        return Button {
            guard section != .settings else { return }
            prefs.setNavigationSection(section.rawValue, visible: !visible)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .foregroundStyle(visible ? section.iconColor : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.rawValue).font(.callout.weight(.semibold))
                    Text(section == .settings ? "Always visible" : (gated ? "Hidden by current mode" : section.group.capitalized))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: visible ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(visible ? WorkbenchTheme.success : .secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(visible ? WorkbenchTheme.accent.opacity(0.10) : Color.secondary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                    .strokeBorder(gated && visible ? Color.orange.opacity(0.35) : WorkbenchTheme.grid)
            }
        }
        .buttonStyle(.plain)
        .disabled(section == .settings)
        .help(section == .settings ? "Settings cannot be hidden." : "Show or hide \(section.rawValue) in the sidebar.")
    }

    private func formatted(_ value: Double, suffix: String) -> String {
        if suffix.isEmpty { return String(format: "%.2f", value) }
        return "\(Int(value.rounded()))\(suffix)"
    }
}
