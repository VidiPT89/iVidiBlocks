import XCTest
@testable import iTetris

/// Guards the three places a string has to exist: the `LocKey` enum and both
/// `.lproj` tables. A key that is missing from one of them shows up in the app
/// as its own raw value, which is the kind of thing nobody notices until a
/// screenshot goes out with `hud.backToBack` printed on it.
final class LocalizationTests: XCTestCase {

    private func table(for language: AppLanguage) throws -> [String: String] {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: language.lprojName, ofType: "lproj"),
            "no \(language.lprojName).lproj in the bundle"
        )
        let bundle = try XCTUnwrap(Bundle(path: path))
        let strings = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: "strings"))
        return try XCTUnwrap(NSDictionary(contentsOfFile: strings) as? [String: String])
    }

    func testEveryKeyIsTranslatedInEveryLanguage() throws {
        for language in AppLanguage.allCases {
            let table = try table(for: language)
            for key in LocKey.allCases {
                let value = table[key.rawValue]
                XCTAssertNotNil(value, "\(language.lprojName) is missing \(key.rawValue)")
                XCTAssertFalse(value?.isEmpty ?? true,
                               "\(language.lprojName) has \(key.rawValue) empty")
            }
        }
    }

    func testNoTranslationIsLeftBehindWithoutAKey() throws {
        let known = Set(LocKey.allCases.map(\.rawValue))
        for language in AppLanguage.allCases {
            let orphans = Set(try table(for: language).keys).subtracting(known).sorted()
            XCTAssertEqual(orphans, [], "\(language.lprojName) has strings no LocKey reaches")
        }
    }

    func testPortugueseAndEnglishSayDifferentThings() throws {
        let pt = try table(for: .pt)
        let en = try table(for: .en)

        // A handful of keys really are the same word in both languages, so
        // this checks the bulk rather than demanding every single one differs.
        let shared = LocKey.allCases.filter { pt[$0.rawValue] == en[$0.rawValue] }
        XCTAssertLessThan(shared.count, LocKey.allCases.count / 4,
                          "too many identical strings, pt-PT looks like a copy of en")
    }

    func testTheManagerResolvesRealTranslationsRatherThanRawKeys() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let manager = LocalizationManager(defaults: defaults)

        manager.setLanguage(.en)
        XCTAssertEqual(manager.string(.commonClose), "Close")

        manager.setLanguage(.pt)
        XCTAssertEqual(manager.string(.commonClose), "Fechar")
    }

    func testTheChosenLanguageSurvivesARelaunch() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        LocalizationManager(defaults: defaults).setLanguage(.pt)
        XCTAssertEqual(LocalizationManager(defaults: defaults).language, .pt)
    }

    /// Choosing the language the device already uses looks like a no-op, but
    /// it still has to be written down, or a later change of device language
    /// would silently overrule the player.
    func testPickingTheLanguageAlreadyShowingIsStillRecorded() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let manager = LocalizationManager(defaults: defaults)
        let showing = manager.language
        manager.setLanguage(showing)

        XCTAssertEqual(defaults.string(forKey: "settings.language"), showing.rawValue)
    }
}
