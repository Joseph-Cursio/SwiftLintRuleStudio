//
//  WorkspaceManager+Config.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

extension WorkspaceManager {
    /// Check if SwiftLint config file exists for current workspace
    func checkConfigFileExists() {
        guard let workspace = currentWorkspace else {
            configFileMissing = false
            return
        }

        let configPath = workspace.configPath ?? workspace.path.appendingPathComponent(".swiftlint.yml")
        configFileMissing = !FileManager.default.fileExists(atPath: configPath.path)
    }

    /// Create a default SwiftLint configuration file for the current workspace
    /// - Returns: URL of the created config file, or nil if creation failed
    @discardableResult
    func createDefaultConfigFile() throws -> URL? {
        guard let workspace = currentWorkspace else {
            throw WorkspaceError.invalidPath
        }

        let configPath = workspace.path.appendingPathComponent(".swiftlint.yml")

        if FileManager.default.fileExists(atPath: configPath.path) {
            return configPath
        }

        try writeDefaultConfig(to: configPath)
        updateWorkspaceConfigPath(configPath, workspace: workspace)
        configFileMissing = false

        return configPath
    }
}

private extension WorkspaceManager {
    static let defaultConfigTemplate = """
    # SwiftLint Configuration
    # This configuration follows best practices for excluding third-party code
    # and setting reasonable defaults for a Swift project.

    # Exclude common build and dependency directories
    excluded:
      - .build                    # Swift Package Manager dependencies
      - Pods                      # CocoaPods dependencies
      - .git                      # Git metadata
      - DerivedData               # Xcode build artifacts
      - .swiftpm                  # Swift Package Manager metadata
      - xcuserdata                # Xcode user-specific data
      - .xcode                    # Xcode project files

    # Disable rules that are too strict for development
    disabled_rules:
      - todo                      # Allow TODO comments during development
      - trailing_whitespace       # Can be handled by Xcode

    # Opt-in rules (enable specific rules that are valuable)
    opt_in_rules:
      - empty_count               # Prefer isEmpty over count == 0
      - empty_string              # Prefer isEmpty over == ""
      - first_where               # Prefer first(where:) over filter.first
      - force_unwrapping          # Warn about force unwraps
      - implicitly_unwrapped_optional  # Warn about IUOs
      - overridden_super_call     # Ensure super calls in overrides
      - prohibited_super_call    # Prevent incorrect super calls
      - redundant_nil_coalescing  # Remove redundant ?? nil
      - single_test_class         # One test class per file
      - unneeded_parentheses_in_closure_argument  # Clean closure syntax
      - vertical_parameter_alignment_on_call  # Align parameters

    # Rule configurations
    line_length:
      warning: 120
      error: 150
      ignores_function_declarations: true
      ignores_comments: true
      ignores_urls: true

    file_length:
      warning: 500
      error: 1000
      ignore_comment_only_lines: true

    function_body_length:
      warning: 50
      error: 100

    function_parameter_count:
      warning: 5
      error: 8

    type_body_length:
      warning: 300
      error: 500

    cyclomatic_complexity:
      warning: 10
      error: 20

    nesting:
      type_level: 2
      function_level: 3

    # Reporter type (xcode, json, csv, checkstyle, junit, html, emoji, sonarqube, markdown)
    reporter: "xcode"

    """

    func writeDefaultConfig(to configPath: URL) throws {
        try Self.defaultConfigTemplate.write(to: configPath, atomically: true, encoding: .utf8)
    }

    func updateWorkspaceConfigPath(_ configPath: URL, workspace: Workspace) {
        var updatedWorkspace = workspace
        updatedWorkspace.configPath = configPath
        currentWorkspace = updatedWorkspace
    }
}
