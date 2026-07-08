//
//  AppLanguage.swift
//  The Cursed Room
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanishLatinAmerica = "es-419"

    var id: String { rawValue }

    var locale: Locale { Locale(identifier: rawValue) }

    var nativeDisplayName: String {
        switch self {
        case .english: return "English"
        case .spanishLatinAmerica: return "Español"
        }
    }
}
