//
//  LanguageManager.swift
//  The Cursed Room
//

import Combine
import Foundation

@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    private let storageKey = "app_language_code"

    @Published private(set) var current: AppLanguage

    private init() {
        if let code = UserDefaults.standard.string(forKey: storageKey),
           let language = AppLanguage(rawValue: code) {
            current = language
        } else {
            current = .english
        }
        apply(current)
    }

    func select(_ language: AppLanguage) {
        guard current != language else { return }
        current = language
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        apply(language)
    }

    func toggleLanguage() {
        select(current == .english ? .spanishLatinAmerica : .english)
    }

    private func apply(_ language: AppLanguage) {
        Bundle.setLanguage(language.rawValue)
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }
}
