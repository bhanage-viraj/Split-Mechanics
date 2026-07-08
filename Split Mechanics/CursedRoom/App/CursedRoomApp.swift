import SwiftUI

@main
struct CursedRoomApp: App {
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some Scene {
        WindowGroup {
            AppCoordinatorView()
                .environment(\.locale, languageManager.current.locale)
                .environmentObject(languageManager)
        }
    }
}
