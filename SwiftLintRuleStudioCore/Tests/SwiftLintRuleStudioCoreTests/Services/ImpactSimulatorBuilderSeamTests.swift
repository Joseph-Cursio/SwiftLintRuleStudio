import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

/// A `SimulationWorkspaceBuilding` that records what it was asked for.
///
/// This is what the seam bought. Every other collaborator in `ImpactSimulator.init` was already
/// injectable — `SwiftLintCLIProtocol`, `DateProvider`, `IDProvider` — and the workspace builder was
/// constructed inside the initializer, so the only way to see what the simulator asked it to mirror
/// was to read the shadow tree off disk *inside the lint handler*, before the simulator's
/// `defer` cleanup removed it. The existing routing tests do exactly that, and racing a cleanup is
/// not how an argument should have to be observed.
private final class RecordingWorkspaceBuilder: SimulationWorkspaceBuilding, @unchecked Sendable {

    private(set) var requests: [(workspace: Workspace, baseConfigPath: URL?)] = []
    let root: URL

    init(root: URL) {
        self.root = root
    }

    func makeWorkspace(
        for workspace: Workspace,
        baseConfigPath: URL?
    ) throws -> SimulationWorkspace {
        requests.append((workspace, baseConfigPath))
        return SimulationWorkspace(root: root, configs: [], fileManager: .default)
    }
}

struct ImpactSimulatorBuilderSeamTests {

    private func makeShadowRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(
            path: "BuilderSeam-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The simulator lints **the root the builder returned**, and asks for it once, with the
    /// workspace and base config path it was handed. Before the seam this could only be checked by
    /// inspecting a directory that was about to be deleted.
    @Test func theSimulatorLintsTheRootTheBuilderReturned() async throws {
        let shadowRoot = try makeShadowRoot()
        let builder = RecordingWorkspaceBuilder(root: shadowRoot)

        let lintedPaths = LintedPathStore()
        let mockCLI = MockSwiftLintCLIActor()
        await mockCLI.setLintCommandHandler { @Sendable _, workspacePath in
            await lintedPaths.record(workspacePath)
            return Data()
        }

        let workspace = Workspace(path: try makeShadowRoot())
        let simulator = ImpactSimulator(swiftLintCLI: mockCLI, workspaceBuilder: builder)
        let seed = workspace.path.appending(path: "seed.yml")
        _ = try? await simulator.simulateRule(
            ruleId: "force_cast", workspace: workspace, baseConfigPath: seed
        )

        #expect(builder.requests.count == 1)
        #expect(builder.requests.first?.workspace.path == workspace.path)
        #expect(builder.requests.first?.baseConfigPath == seed)
        #expect(await lintedPaths.paths == [shadowRoot])
    }
}

private actor LintedPathStore {
    private(set) var paths: [URL] = []
    func record(_ path: URL) { paths.append(path) }
}
