//
//  TestNavigationView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/7.
//

import SwiftUI
import ComposableArchitecture

struct ScreenA: ReducerProtocol {
    struct State: Codable, Equatable, Hashable {
        var count = 0
    }
    
    enum Action: Equatable {
        case decrementButtonTapped
    }

    func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
        switch action {
            case .decrementButtonTapped:
                state.count -= 1
                return .none
           
        }
    }
}

struct TestNavigationView: View {
    let store: StoreOf<ScreenA>
    
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}
