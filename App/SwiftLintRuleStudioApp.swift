//
//  SwiftLintRuleStudioApp.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI

@main
struct SwiftLintRuleStudioApp: App {
    @StateObject private var ruleRegistry: RuleRegistry
    @StateObject private var dependencyContainer: DependencyContainer
    
    init() {
        let cacheManager = CacheManager()
        let swiftLintCLI = SwiftLintCLI(cacheManager: cacheManager)
        let ruleRegistry = RuleRegistry(swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)
        let container = DependencyContainer()
        
        _ruleRegistry = StateObject(wrappedValue: ruleRegistry)
        _dependencyContainer = StateObject(wrappedValue: container)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ruleRegistry)
                .environmentObject(dependencyContainer)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            
            // Add File menu commands
            CommandGroup(after: .newItem) {
                Button("Open Workspace...") {
                    // This will be handled by the workspace selection view
                    // For now, we'll add a menu item that triggers the file picker
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

