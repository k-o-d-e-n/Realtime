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
            Image(uiImage: model.image ?? UIImage())
            TupleView(
                (
                    Text("Name").bold(),
                    Text(model.name ?? "").italic()
                )
            )
            TupleView(
                (
                    Text("Age").bold(),
                    Text(model.age ?? "").italic()
                )
            )
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
    @Published var image: UIImage?

    let user: User

    init(_ user: User) {
        self.user = user
    }

    func load() {
        _ = user.name.loadValue()
            .sink(
                receiveCompletion: { compl in
                    print(compl)
                },
                receiveValue: { (val) in
                    self.name = val
                }
        )
        _ = ("birthdate".date(in: user) as Property<Date>).loadValue()
        .sink(
            receiveCompletion: { compl in
                print(compl)
            },
            receiveValue: { (date) in
                self.age = "\(date)"
            }
        )
        _ = ("photo".readonlyJpeg(in: user) as ReadonlyFile<UIImage?>).loadValue()
        .sink(
            receiveCompletion: { (compl) in
                print(compl)
            },
            receiveValue: { (image) in
                self.image = image
            }
        )
    }
}
