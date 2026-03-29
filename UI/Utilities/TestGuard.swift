import Foundation
import SwiftUI
import SwiftLintRuleStudioCore

enum TestGuard {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    private static var shouldSuppressAlerts: Bool {
        isRunningTests || isUITesting
    }

    static func alertBinding(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue && !shouldSuppressAlerts },
            set: { binding.wrappedValue = $0 }
        )
    }
}
