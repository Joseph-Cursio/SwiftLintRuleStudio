//
//  SwiftLintRuleStudioApp.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI
#if os(macOS)
import AppKit
import UserNotifications
#endif

@main
struct SwiftLintRuleStudioApp: App {
    @StateObject private var ruleRegistry: RuleRegistry
    @StateObject private var dependencyContainer: DependencyContainer
#if os(macOS)
    @NSApplicationDelegateAdaptor(UITestWindowBootstrapper.self)
    private var uiTestWindowBootstrapper
#endif
    
    init() {
        let cacheManager = CacheManager()
        let swiftLintCLI = SwiftLintCLI(cacheManager: cacheManager)
        let ruleRegistry = RuleRegistry(swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)
        let container = DependencyContainer(
            ruleRegistry: ruleRegistry, swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)
        
        _ruleRegistry = StateObject(wrappedValue: ruleRegistry)
        _dependencyContainer = StateObject(wrappedValue: container)
#if os(macOS)
        UITestWindowBootstrapper.dependencies = (ruleRegistry, container)
#endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ruleRegistry)
                .environmentObject(dependencyContainer)
                .task { await requestNotificationPermission() }
        }
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentMinSize)
        .commands { appCommands }

        Settings {
            AppSettingsView()
                .environmentObject(dependencyContainer)
        }
    }
    
    @CommandsBuilder
    var appCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Workspace…") {
                NotificationCenter.default.post(name: .openWorkspaceRequested, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandMenu("View") {
            Button("Toggle Detail Panel") {
                NotificationCenter.default.post(name: .toggleDetailPanelRequested, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }

        CommandMenu("Lint") {
            Button("Reload Rules") {
                Task { _ = try? await ruleRegistry.loadRules() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Run Lint") {
                NotificationCenter.default.post(name: .violationInspectorRefreshRequested, object: nil)
            }
            .keyboardShortcut(.return, modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("SwiftLint Rule Studio Help") {
                NSWorkspace.shared.open(URL(string: "https://github.com/realm/SwiftLint")!)
            }
            Button("SwiftLint Rule Reference") {
                NSWorkspace.shared.open(
                    URL(string: "https://realm.github.io/SwiftLint/rule-directory.html")!)
            }
            Divider()
            Button("Report an Issue…") {
                NSWorkspace.shared.open(
                    URL(string: "https://github.com/Joseph-Cursio/SwiftLintRuleStudio/issues")!)
            }
        }

        SidebarCommands()
    }

#if os(macOS)
    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound])
    }
#endif
}

struct AppSettingsView: View {
    @EnvironmentObject var dependencies: DependencyContainer

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            LintSettingsView()
                .tabItem { Label("Linting", systemImage: "chevron.left.forwardslash.chevron.right") }
        }
        .padding()
        .frame(width: 520, height: 380)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("autoUpdate") private var autoUpdate = true
    @AppStorage("sendUsageData") private var sendUsageData = false

    var body: some View {
        Form {
            Toggle("Check for updates automatically", isOn: $autoUpdate)
            Toggle("Send anonymous usage data", isOn: $sendUsageData)
        }
        .padding()
    }
}

struct LintSettingsView: View {
    @AppStorage("experimentalRules") private var experimentalRules = false
    @AppStorage("inlineHints") private var inlineHints = true

    var body: some View {
        Form {
            Toggle("Enable experimental rules", isOn: $experimentalRules)
            Toggle("Show inline hints", isOn: $inlineHints)
        }
        .padding()
    }
}

#if os(macOS)
@MainActor
final class UITestWindowBootstrapper: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var dependencies: (RuleRegistry, DependencyContainer)?
    /// Retained to prevent ARC from deallocating the window after creation.
    /// Never read directly — ownership is the sole purpose of this property.
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        guard ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        guard NSApp.windows.isEmpty else { return }
        guard let dependencies = Self.dependencies else { return }

        let rootView = ContentView()
            .environmentObject(dependencies.0)
            .environmentObject(dependencies.1)
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SwiftLIntRuleStudio"
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let workspaceManager = Self.dependencies?.1.workspaceManager else { return nil }
        let recentWorkspaces = workspaceManager.recentWorkspaces.prefix(5)
        guard !recentWorkspaces.isEmpty else { return nil }

        let menu = NSMenu()
        for workspace in recentWorkspaces {
            let item = NSMenuItem(
                title: workspace.name,
                action: #selector(openRecentWorkspaceFromDock(_:)),
                keyEquivalent: ""
            )
            item.representedObject = workspace.path
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openRecentWorkspaceFromDock(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        try? Self.dependencies?.1.workspaceManager.openWorkspace(at: url)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
        }
        completionHandler()
    }
}
#endif
