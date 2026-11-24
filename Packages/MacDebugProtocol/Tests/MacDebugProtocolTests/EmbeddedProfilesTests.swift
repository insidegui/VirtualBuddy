import Foundation
import Testing
@testable import MacDebugProtocol

struct EmbeddedProfilesTests {
    @Test func findsNestedBundlesWithoutTraversingSymlinkedDirectories() async throws {
        try await DebugTools.withTemporaryDirectory { root in
            let app = root.appendingPathComponent("Main.app")
            let paths = ["Main.app/Contents", "Main.app/Contents/PlugIns/Example.appex/Contents",
                         "Main.app/Contents/Library/LoginItems/Helper.app/Contents", "Outside.app/Contents"]
            for path in paths {
                let directory = root.appendingPathComponent(path)
                try DebugTools.directory(directory)
                try Data().write(to: directory.appendingPathComponent("embedded.provisionprofile"))
            }
            try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("Contents/Other.app"),
                                                      withDestinationURL: root.appendingPathComponent("Outside.app"))
            let profiles = try EmbeddedProfiles.find(in: app)
            #expect(profiles.count == 3)
            let expected = paths.dropLast().map { root.appendingPathComponent($0 + "/embedded.provisionprofile").resolvingSymlinksInPath().standardizedFileURL.path }
            #expect(Set(profiles.map(\.path)) == Set(expected))
        }
    }
}
