//
//  SwiftLintRuleStudioApp.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI
#if os(macOS)
import AppKit
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
        }
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
                // This will be handled by the workspace selection view or a coordinator
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandMenu("Lint") {
            Button("Reload Rules") {
                Task { _ = try? await ruleRegistry.loadRules() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Run Lint") {
                // Trigger lint run if available
            }
            .keyboardShortcut(.return, modifiers: .command)
        }

        SidebarCommands()
    }
}

struct AppSettingsView: View {
    @EnvironmentObject var dependencies: DependencyContainer

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Text("General") }
            LintSettingsView()
                .tabItem { Text("Linting") }
        }
        .padding()
        .frame(width: 520, height: 380)
    }
}

// Placeholder settings tabs to ensure the Settings window compiles
struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Toggle("Check for updates automatically", isOn: .constant(true))
            Toggle("Send anonymous usage data", isOn: .constant(false))
        }
        .padding()
    }
}

struct LintSettingsView: View {
    var body: some View {
        Form {
            Toggle("Enable experimental rules", isOn: .constant(false))
            Toggle("Show inline hints", isOn: .constant(true))
        }
        .padding()
    }
}

#if os(macOS)
@MainActor
final class UITestWindowBootstrapper: NSObject, NSApplicationDelegate {
    static var dependencies: (RuleRegistry, DependencyContainer)?
    /// Retained to prevent ARC from deallocating the window after creation.
    /// Never read directly — ownership is the sole purpose of this property.
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
}
#endif
