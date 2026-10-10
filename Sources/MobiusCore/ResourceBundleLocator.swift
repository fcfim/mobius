import Foundation

/// Locates a SwiftPM resource bundle (`<Package>_<Target>.bundle`) **without ever calling fatalError**.
///
/// The `Bundle.module` accessor that SwiftPM generates kills the process when it cannot find the
/// bundle, and where it looks depends on the build system (both observed in the generated sources):
/// - native build system (default up to Swift 6.2; `--build-system native` on 6.4):
///   `Bundle.main.bundleURL/<name>.bundle` (the app **root**, not `Contents/Resources`), then the
///   **absolute** `.build/.../release/<name>.bundle` path of the machine that built it. App bundles keep
///   resources in `Contents/Resources`, so the first candidate always misses and the second exists only
///   on the build Mac. A release app installed anywhere else crashes on first access (issue #27).
/// - swiftbuild (default on Swift 6.4): `Bundle.main.resourceURL`, then the framework, then `bundleURL`.
///
/// So the app does not use the accessor. It searches both layouts directly and returns nil when the
/// bundle is missing, letting the caller fall back to the untranslated source strings.
public enum ResourceBundleLocator {
    /// The first `<dir>/<name>.bundle` that exists in `candidates`, in order. nil if none does.
    public static func locate(named name: String, in candidates: [URL],
                              fileManager: FileManager = .default) -> Bundle? {
        for dir in candidates {
            let url = dir.appendingPathComponent(name + ".bundle", isDirectory: true)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                  let bundle = Bundle(url: url) else { continue }
            return bundle
        }
        return nil
    }

    /// Candidate directories for each way the app can run (deduplicated, order preserved):
    /// 1. `Contents/Resources`: packaged .app (make-app.sh copies the bundle here)
    /// 2. bundle root: where the native accessor looked (the executable's directory for a bare binary)
    /// 3. executable directory: where `swift run` / `.build/release` put the bundle, next to the binary
    public static func defaultCandidates(resourceURL: URL?, bundleURL: URL?, executableURL: URL?) -> [URL] {
        var seen = Set<String>()
        return [resourceURL, bundleURL, executableURL?.deletingLastPathComponent()]
            .compactMap { $0?.standardizedFileURL }
            .filter { seen.insert($0.path).inserted }
    }

    /// Searches the candidates derived from `Bundle.main`. Entry point for the app.
    public static func locateInMainBundle(named name: String) -> Bundle? {
        let main = Bundle.main
        return locate(named: name, in: defaultCandidates(resourceURL: main.resourceURL,
                                                         bundleURL: main.bundleURL,
                                                         executableURL: main.executableURL))
    }
}
