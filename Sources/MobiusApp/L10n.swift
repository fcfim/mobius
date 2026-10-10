import Foundation
import MobiusCore

/// 앱 UI 다국어. 키 = 한국어 원문.
/// "system"이면 macOS 선호 언어를 따르고(ko/en/ja/pt/es 매칭, 없으면 en), 아니면 지정 언어 고정.
/// Missing translations fall back to English first, then to the Korean source text.
enum L10n {
    static let defaultsKey = "appLanguage" // "system" | "ko" | "en" | "ja" | "pt" | "es"
    static let supported = ["ko", "en", "ja", "pt", "es"]

    static var current: String {
        UserDefaults.standard.string(forKey: defaultsKey) ?? "system"
    }

    static func setLanguage(_ lang: String) {
        UserDefaults.standard.set(lang, forKey: defaultsKey)
        cachedLang = nil
    }

    private static var cachedLang: String?
    private static var cachedBundle: Bundle?

    private static func resolvedLang() -> String {
        let pref = current
        if pref != "system" { return pref }
        for l in Locale.preferredLanguages {
            let code = String(l.prefix(2))
            if supported.contains(code) { return code }
        }
        return "en"
    }

    /// SwiftPM resource bundle name (`<Package>_<Target>`). make-app.sh copies it into
    /// `Contents/Resources` under this name.
    static let resourceBundleName = "Mobius_MobiusApp"

    /// Localization resource bundle. **Do not use `Bundle.module`**: that accessor calls fatalError
    /// when the bundle is missing, and with the native build system (Swift <= 6.2) it only checks the
    /// app root and the build Mac's absolute `.build` path. Release apps installed on any other Mac
    /// crashed as soon as they ran in en/ja (issue #27, five crash reports on macOS 26).
    /// nil when missing, so strings fall back to the Korean source text.
    private static let resourceBundle: Bundle? =
        ResourceBundleLocator.locateInMainBundle(named: resourceBundleName)

    /// nil = 한국어(키 원문 그대로 사용). en/ja는 해당 lproj 서브번들을 **직접** 연다 —
    /// Bundle.module에 위임하면 CFBundle이 시스템 언어 기준으로 en을 골라버려서
    /// (ko.lproj가 없으므로) 한국어 사용자에게 영어가 나온다 (실측 버그).
    static func bundle() -> Bundle? {
        let lang = resolvedLang()
        if lang == "ko" { return nil }
        if lang == cachedLang, let b = cachedBundle { return b }
        guard let path = resourceBundle?.path(forResource: lang, ofType: "lproj"),
              let b = Bundle(path: path) else { return nil } // no bundle/lproj: show source text
        cachedLang = lang
        cachedBundle = b
        return b
    }

    /// English sub-bundle, used as the fallback for keys a translation does not have yet.
    private static let cachedEnglish: Bundle? =
        resourceBundle?.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))

    static func englishBundle() -> Bundle? { cachedEnglish }
}

/// 모든 사용자 노출 문자열은 이 함수를 거친다. 키가 곧 한국어 원문.
func loc(_ key: String) -> String {
    guard let b = L10n.bundle() else { return key }
    let value = b.localizedString(forKey: key, value: key, table: nil)
    // A key missing from pt/es/ja would otherwise show Korean; prefer English.
    if value == key, let en = L10n.englishBundle(), en !== b {
        return en.localizedString(forKey: key, value: key, table: nil)
    }
    return value
}

/// 포맷 인자 버전 — 키는 %@/%d 포함 한국어 포맷 문자열.
func loc(_ key: String, _ args: CVarArg...) -> String {
    String(format: loc(key), arguments: args)
}
