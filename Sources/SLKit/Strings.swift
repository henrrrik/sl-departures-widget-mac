import Foundation

/// SLKit writes a handful of words of its own — "now", the transport modes, the
/// filter summary, the failure text — and they have to be in the same language
/// as the UI around them.
///
/// The language is a seam rather than `Locale.current` so that `swift test`
/// reads the same on a Swedish Mac as on an English one: the model defaults to
/// English, and the two bundles opt into the system's language at launch.
public enum SLLanguage {
    nonisolated(unsafe) public static var locale = Locale(identifier: "en")

    /// What a running app wants: the language the UI around these words is
    /// already drawn in. That is the bundle's chosen localization, not
    /// `Locale.current` — a Swedish region with an English UI is English.
    public static func followSystem() {
        locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}

/// One lookup, so every localized word in SLKit goes through the same seam.
/// A key with no translation falls back to itself, which is the English text.
func t(_ key: String.LocalizationValue) -> String {
    localized(key, in: SLLanguage.locale)
}

/// The lookup with the language spelled out, which is how the tests reach it
/// without moving the seam under any test running beside them.
///
/// The `.lproj` is resolved by hand because `String(localized:locale:)` uses
/// its locale to format the arguments, not to choose the translation — that
/// choice otherwise follows the host process's languages, which for the widget
/// extension and for `swift test` is not the language we mean.
func localized(_ key: String.LocalizationValue, in locale: Locale) -> String {
    String(localized: key, bundle: catalog(for: locale), locale: locale)
}

private func catalog(for locale: Locale) -> Bundle {
    guard let code = locale.language.languageCode?.identifier,
          let path = Bundle.module.path(forResource: code, ofType: "lproj"),
          let bundle = Bundle(path: path)
    else { return .module }
    return bundle
}
