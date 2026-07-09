//
//  GameplayRouter.swift
//  The Cursed Room
//
//  Phase 6 navigation hooks (letter reveal, seal hunt, etc.).
//

import Combine
import Foundation

@MainActor
protocol GameplayRouterProtocol: AnyObject {
    func endGameAfterFirstSeal()
}

@MainActor
final class GameplayRouter: ObservableObject, GameplayRouterProtocol {

    @Published private(set) var shouldEndGame = false

    func endGameAfterFirstSeal() {
        guard !shouldEndGame else { return }
        shouldEndGame = true
        print("🏁 [Gameplay] Blood pool puzzle solved — ending game")
    }
}
