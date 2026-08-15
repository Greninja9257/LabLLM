import SwiftUI

@main
struct LabLLMApp: App {
    @StateObject private var state = AppState()
    @StateObject private var prefs = Preferences()
    @StateObject private var server = ModelServer()
    @StateObject private var tutorial = TutorialState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        _ = try? MLXMetalLibrary.ensureAvailable()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(state.trainer)   // nested object observed directly
                .environmentObject(state.loading)
                .environmentObject(prefs)
                .environmentObject(server)
                .environmentObject(tutorial)
                .frame(minWidth: 1040, minHeight: 700)
                .preferredColorScheme(prefs.appearance.colorScheme)
                .tint(prefs.accent.color)
                .onAppear { appDelegate.trainer = state.trainer }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Show Welcome Screen") { NotificationCenter.default.post(name: .showWelcome, object: nil) }
                Button("Replay Tutorial") { NotificationCenter.default.post(name: .showTutorial, object: nil) }
            }
        }
    }
}

extension Notification.Name {
    static let showWelcome = Notification.Name("labllm.showWelcome")
    static let showTutorial = Notification.Name("labllm.showTutorial")
}
