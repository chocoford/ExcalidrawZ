//
//  TestView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import SwiftUI

struct Item: Identifiable, Hashable {
    var id = UUID()
    var text: String
}

struct Player: Identifiable {
    var id = UUID()
    var score: String
}

struct TestView: View {
    @State var sidebarItems: [Item] = [
        .init(text: "1"),
        .init(text: "2")
    ]
    
    @State var players: [Player] = [
        .init(score: "2"),
        .init(score: "3"),
        .init(score: "6"),
        .init(score: "1")]
    
    @State private var selectedItem: Item?
    
    var body: some View {
       Text("Hello")
    }
}

struct TestView_Previews: PreviewProvider {
    static var previews: some View {
        TestView()
    }
}
