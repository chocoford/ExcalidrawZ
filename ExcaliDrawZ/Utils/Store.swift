//
//  Store.swift
//  CSWang
//
//  Created by Dove Zachary on 2022/11/28.
//

import SwiftUI
import Combine
import OSLog

struct Reducer<State, Action, Environment> {
    let reduce: (inout State, Action, Environment) -> AnyPublisher<Action, Never>
    
    func callAsFunction(
        _ state: inout State,
        _ action: Action,
        _ environment: Environment
    ) -> AnyPublisher<Action, Never> {
        reduce(&state, action, environment)
    }
}

@MainActor
final class Store<State, Action, Environment>: ObservableObject {
    @Published private(set) var state: State
    
    private let reducer: (inout State, Action) -> AnyPublisher<Action, Never>
    private var effectCancellables: [UUID: AnyCancellable] = [:]
    private let queue: DispatchQueue
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Store")

    init(state: State, reducer: Reducer<State, Action, Environment>, environment: Environment,
         subscriptionQueue: DispatchQueue = .init(label: "com.chocoford.ExcalidrawZ.store")) {
        self.state = state
        self.reducer = { state, action in
            reducer(&state, action, environment)
        }
        self.queue = subscriptionQueue
    }
    
    
    @available(*, deprecated, message: "Not ready")
    func send(_ action: Action) async {
        logger.info("send: \(String(describing: action))")
        /// AnyPublisher<Action, Never>
        let effect = reducer(&state, action)
        
        for await action in effect.values {
            await send(action)
        }
    }
    
    func send(_ action: Action) {
        logger.info("send: \(String(describing: action))")
        /// AnyPublisher<Action, Never>
        let effect = reducer(&state, action)
        
        var didComplete = false
        let uuid = UUID()
        
        let cancellable = effect
            .subscribe(on: queue)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] _ in
                    didComplete = true
                    self?.effectCancellables[uuid] = nil
                },
                receiveValue: { [weak self] in self?.send($0) }
            )
        
        if !didComplete {
            effectCancellables[uuid] = cancellable
        }
    }
}

extension Store {
    func binding<Value>(
        for keyPath: KeyPath<State, Value>,
        toAction: @escaping (Value) -> Action
    ) -> Binding<Value> {
        Binding<Value>(
            get: { self.state[keyPath: keyPath] },
            set: { self.send(toAction($0)) }
        )
    }
}

