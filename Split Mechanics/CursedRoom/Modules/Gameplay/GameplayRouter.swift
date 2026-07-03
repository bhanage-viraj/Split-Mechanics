//
//  GameplayRouter.swift
//  The Cursed Room
//
//  Phase 6 navigation hooks (letter reveal, seal hunt, etc.).
//

import Combine
import Foundation

@MainActor
protocol GameplayRouterProtocol: AnyObject {}

@MainActor
final class GameplayRouter: ObservableObject, GameplayRouterProtocol {}
