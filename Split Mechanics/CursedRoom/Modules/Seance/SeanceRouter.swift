//
//  SeanceRouter.swift
//  The Cursed Room
//
//  Phase 4 → Phase 5 navigation.
//

import Combine
import Foundation

@MainActor
protocol SeanceRouterProtocol: AnyObject {
    func routeToPhase5()
}

@MainActor
final class SeanceRouter: ObservableObject, SeanceRouterProtocol {
    /// Observed by the AppCoordinator to present the curse-begins transition.
    @Published var shouldShowPhase5: Bool = false

    func routeToPhase5() {
        guard !shouldShowPhase5 else { return }
        shouldShowPhase5 = true
        print("🕯️ [Seance] Routing to Phase 5 — The Curse Has Begun")
    }
}
