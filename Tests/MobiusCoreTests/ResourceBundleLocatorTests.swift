import XCTest
@testable import MobiusCore

/// Locator for the app's localization bundle (`Mobius_MobiusApp.bundle`) that never calls fatalError.
/// SwiftPM's `Bundle.module` accessor looks in different places per build system (native: app root
/// plus the build Mac's absolute .build path; swiftbuild: Contents/Resources) and calls fatalError
/// when it finds nothing. That caused issue #27: en/ja users crashed as soon as the popover opened.
final class ResourceBundleLocatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rbl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates `<dir>/Mobius_MobiusApp.bundle/Contents/Resources/<lang>.lproj/Localizable.strings`.
    private func makeBundle(in dir: URL, langs: [String]) throws -> URL {
        let bundle = dir.appendingPathComponent("Mobius_MobiusApp.bundle", isDirectory: true)
        for lang in langs {
            let lproj = bundle.appendingPathComponent("Contents/Resources/\(lang).lproj", isDirectory: true)
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            try #""계정" = "Accounts (\#(lang))";"#
                .write(to: lproj.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        }
        return bundle
    }

    /// Packaged app: the bundle lives under Contents/Resources (Bundle.main.resourceURL).
    func testFindsBundleUnderResourcesDirectory() throws {
        let resources = root.appendingPathComponent("Mobius.app/Contents/Resources", isDirectory: true)
        let expected = try makeBundle(in: resources, langs: ["en", "ja"])
        let found = ResourceBundleLocator.locate(named: "Mobius_MobiusApp",
                                                 in: [resources, root.appendingPathComponent("Mobius.app")])
        XCTAssertEqual(found?.bundleURL.standardizedFileURL, expected.standardizedFileURL)
        XCTAssertNotNil(found?.path(forResource: "en", ofType: "lproj"))
        XCTAssertNotNil(found?.path(forResource: "ja", ofType: "lproj"))
    }

    /// Native build system (Swift <= 6.2) bundles have no Contents/; `<lang>.lproj` sits at the root.
    func testFindsLprojInFlatBundleLayout() throws {
        let bundle = root.appendingPathComponent("Mobius_MobiusApp.bundle/en.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try #""계정" = "Accounts";"#.write(to: bundle.appendingPathComponent("Localizable.strings"),
                                           atomically: true, encoding: .utf8)
        let found = ResourceBundleLocator.locate(named: "Mobius_MobiusApp", in: [root])
        let lproj = try XCTUnwrap(found?.path(forResource: "en", ofType: "lproj"))
        XCTAssertEqual(Bundle(path: lproj)?.localizedString(forKey: "계정", value: "계정", table: nil), "Accounts")
    }

    /// The layout 0.5.5 actually shipped: a flat native bundle inside the packaged app's
    /// Contents/Resources, searched with the app's real candidate order (nothing at the app root,
    /// which is where the native accessor looked).
    func testFindsFlatBundleInsidePackagedAppResources() throws {
        let app = root.appendingPathComponent("Mobius.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let lproj = resources.appendingPathComponent("Mobius_MobiusApp.bundle/ja.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        try #""계정" = "アカウント";"#.write(to: lproj.appendingPathComponent("Localizable.strings"),
                                              atomically: true, encoding: .utf8)
        let candidates = ResourceBundleLocator.defaultCandidates(
            resourceURL: resources, bundleURL: app,
            executableURL: app.appendingPathComponent("Contents/MacOS/MobiusApp"))
        let found = ResourceBundleLocator.locate(named: "Mobius_MobiusApp", in: candidates)
        let path = try XCTUnwrap(found?.path(forResource: "ja", ofType: "lproj"))
        XCTAssertEqual(Bundle(path: path)?.localizedString(forKey: "계정", value: "계정", table: nil), "アカウント")
        XCTAssertNil(found?.path(forResource: "en", ofType: "lproj")) // missing lproj is nil, no crash
    }

    /// `swift run` / `.build/release`: the bundle sits next to the executable. Missing candidates are skipped.
    func testFallsThroughMissingCandidatesToFlatLayout() throws {
        let missing = root.appendingPathComponent("nope/Contents/Resources", isDirectory: true)
        let flat = root.appendingPathComponent("build", isDirectory: true)
        let expected = try makeBundle(in: flat, langs: ["en"])
        let found = ResourceBundleLocator.locate(named: "Mobius_MobiusApp", in: [missing, flat])
        XCTAssertEqual(found?.bundleURL.standardizedFileURL, expected.standardizedFileURL)
    }

    /// Core regression: no bundle anywhere returns nil and never crashes (caller shows source strings).
    func testReturnsNilWhenBundleMissingEverywhere() {
        let found = ResourceBundleLocator.locate(named: "Mobius_MobiusApp",
                                                 in: [root, root.appendingPathComponent("x")])
        XCTAssertNil(found)
    }

    /// Real app candidate order: Contents/Resources, bundle root, executable directory. nil is skipped.
    func testDefaultCandidatesCoverAppAndBareExecutableLayouts() {
        let appURL = URL(fileURLWithPath: "/Applications/Mobius.app")
        let candidates = ResourceBundleLocator.defaultCandidates(
            resourceURL: appURL.appendingPathComponent("Contents/Resources"),
            bundleURL: appURL,
            executableURL: appURL.appendingPathComponent("Contents/MacOS/MobiusApp"))
        XCTAssertEqual(candidates.map(\.path), [
            "/Applications/Mobius.app/Contents/Resources",
            "/Applications/Mobius.app",
            "/Applications/Mobius.app/Contents/MacOS",
        ])
        // Bare executable (swift run): resourceURL == bundleURL == executable directory, deduplicated
        let bare = URL(fileURLWithPath: "/tmp/.build/release")
        XCTAssertEqual(ResourceBundleLocator.defaultCandidates(
            resourceURL: bare, bundleURL: bare,
            executableURL: bare.appendingPathComponent("MobiusApp")).map(\.path), ["/tmp/.build/release"])
        XCTAssertEqual(ResourceBundleLocator.defaultCandidates(
            resourceURL: nil, bundleURL: bare, executableURL: nil).map(\.path), ["/tmp/.build/release"])
    }
}
