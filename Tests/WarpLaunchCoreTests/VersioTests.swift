import Foundation
import Testing
@testable import WarpLaunchCore

@Test func laVersioCoincideixAmbElFitxerVERSION() throws {
    let arrel = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // WarpLaunchCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // arrel del repo
    let fitxer = try String(contentsOf: arrel.appendingPathComponent("VERSION"), encoding: .utf8)
    #expect(fitxer.trimmingCharacters(in: .whitespacesAndNewlines) == WarpLaunch.versio)
}
