import SwiftUI

/// First-launch welcome + mode selection. Shown until the user finishes onboarding;
/// re-openable from Settings.
struct WelcomeView: View {
    @EnvironmentObject var prefs: Preferences
    @Environment(\.dismiss) private var dismiss
    var onFinish: () -> Void

    @State private var page = 0
    private let pages = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                intro.tag(0)
                modePicker.tag(1)
                flow.tag(2)
            }
            .tabViewStyle(.automatic)
            .frame(minHeight: 420)

            Divider()
            HStack {
                if page > 0 {
                    Button("Back") { withAnimation { page -= 1 } }
                }
                Spacer()
                PageDots(count: pages, index: page)
                Spacer()
                if page < pages - 1 {
                    Button("Next") { withAnimation { page += 1 } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get started") {
                        prefs.hasOnboarded = true
                        onFinish()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(WorkbenchPrimaryButtonStyle())
                }
            }
            .padding()
        }
        .frame(width: 640, height: 520)
    }

    private var intro: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64)).foregroundStyle(.tint)
            Text("Welcome to LabLLM").font(.largeTitle.bold())
            Text("Design, train, and sample small GPT language models locally on your Mac — powered by Apple MLX. No cloud, no account.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
        }.padding(40)
    }

    private var modePicker: some View {
        VStack(spacing: 16) {
            Text("Pick your comfort level").font(.title.bold())
            Text("You can change this anytime in Settings.").foregroundStyle(.secondary)
            ForEach(AppMode.allCases) { mode in
                Button {
                    prefs.mode = mode
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: mode.icon).font(.title2).frame(width: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.label).font(.headline)
                            Text(mode.blurb).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: prefs.mode == mode ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(prefs.mode == mode ? Color.accentColor : .secondary)
                    }
                    .padding(14)
                    .background(prefs.mode == mode ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }.padding(40)
    }

    private var flow: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The basic flow").font(.title.bold()).frame(maxWidth: .infinity, alignment: .center)
            step("1", "cube.transparent", "Design a model", "Choose a size preset or tune the architecture.")
            step("2", "text.book.closed", "Bring data", "Use the built-in sample or import a .txt file, then build a tokenizer.")
            step("3", "waveform.path.ecg", "Train", "Watch the loss drop live. Pause or stop anytime.")
            step("4", "text.cursor", "Sample", "Generate text from your trained model.")
            Text("Tip: turn on the tutorial from the toolbar if you'd like guided coach-marks.")
                .font(.footnote).foregroundStyle(.secondary).padding(.top, 6)
        }.padding(40)
    }

    private func step(_ n: String, _ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(spacing: 14) {
            Text(n).font(.headline.monospacedDigit())
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Image(systemName: icon).frame(width: 24).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(desc).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct PageDots: View {
    let count: Int; let index: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { i in
                Circle().fill(i == index ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }
}
