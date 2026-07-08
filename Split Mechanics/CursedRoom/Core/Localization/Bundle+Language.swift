//
//  Bundle+Language.swift
//  The Cursed Room
//

import Foundation
import ObjectiveC

private var languageBundleKey: UInt8 = 0

extension Bundle {
    static func setLanguage(_ languageCode: String) {
        defer {
            object_setClass(Bundle.main, LocalizedBundle.self)
        }

        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            objc_setAssociatedObject(
                Bundle.main,
                &languageBundleKey,
                nil,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            return
        }

        objc_setAssociatedObject(
            Bundle.main,
            &languageBundleKey,
            bundle,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    fileprivate static var languageBundle: Bundle? {
        objc_getAssociatedObject(Bundle.main, &languageBundleKey) as? Bundle
    }
}

private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(
        forKey key: String,
        value: String?,
        table tableName: String?
    ) -> String {
        if let bundle = Bundle.languageBundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
