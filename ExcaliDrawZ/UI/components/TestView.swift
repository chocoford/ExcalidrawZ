//
//  TestView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import SwiftUI

struct Player: Identifiable {
    var id = UUID()
    var score: String
}

struct TestView: View {
    @State var players: [Player] = [
        .init(score: "2"),
        .init(score: "3"),
        .init(score: "6"),
        .init(score: "1")]
    var body: some View {
        VStack {
            Button("shuffle") {
                withAnimation(.easeIn) {
                    players = players.shuffled()
                }
            }
            List {
                ForEach(players) { player in
                    Text(player.score)
                }
            }
        }
    }
}

struct TestView_Previews: PreviewProvider {
    static var previews: some View {
        TestView()
    }
}
