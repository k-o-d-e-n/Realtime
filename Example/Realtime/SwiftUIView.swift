//
//  SwiftUIView.swift
//  Realtime_Example
//
//  Created by Denis Koryttsev on 07.11.2019.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import SwiftUI
import Realtime

@available(iOS 13.0.0, *)
struct SwiftUIView: View {
    @ObservedObject var model: SwiftUIViewModel

    init(user: User) {
        self.model = SwiftUIViewModel(user)
    }

    var body: some View {
        VStack {
            Text(model.name ?? "")
            Text(model.age ?? "")
        }.onAppear {
            self.model.load()
        }
    }
}

#if DEBUG
@available(iOS 13.0.0, *)
struct SwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        SwiftUIView(user: User(in: Global.rtUsers.node?.child(with: "user")))
    }
}
#endif

@available(iOS 13.0.0, *)
class SwiftUIViewModel: ObservableObject {
    @Published var name: String?
    @Published var age: String?

    let user: User

    init(_ user: User) {
        self.user = user
    }

    func load() {
        _ = user.load()
            .completion
            .sink(
                receiveCompletion: { compl in
                    print(compl)
                },
                receiveValue: { (val) in
                    self.name = self.user.name.wrapped
    //                self.age = self.user.
                }
        )
    }
}
