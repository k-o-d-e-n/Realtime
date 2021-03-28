//
//  SwiftUIView.swift
//  Realtime_Example
//
//  Created by Denis Koryttsev on 07.11.2019.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

#if canImport(Combine)
import SwiftUI
import Realtime
import Combine

@available(iOS 13.0.0, *)
struct SwiftUIView: View {
    @ObservedObject var model: SwiftUIViewModel
    @State var loading: Bool = false
    var cancels: ListeningDisposeStore = ListeningDisposeStore()

    init(user: User1) {
        self.model = SwiftUIViewModel(user)
    }

    var body: some View {
        VStack {
            if !loading {
                Image(uiImage: model.image ?? UIImage()).cornerRadius(10)
                TupleView(
                    (
                        Text("Name").italic(),
                        Text(model.name ?? "").bold()
                    )
                )
                TupleView(
                    (
                        Text("Birthdate").italic(),
                        Text(model.birthdate ?? "").bold()
                    )
                )
            } else {
                ActivityIndicator(isAnimating: $loading, style: .large)
            }
        }.onAppear(perform: onAppear)
    }

    func onAppear() {
        self.loading = true
        self.model
            .load()
            .delay(for: .seconds(1), scheduler: DispatchQueue.main)
            .map({ _ in false })
            .bind(to: self, \.loading, onCompletion: { _ in self.loading = false })
            .add(to: self.cancels)
    }
}

#if DEBUG
@available(iOS 13.0.0, *)
struct SwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        SwiftUIView(user: User1(in: Global.rtUsers.node?.child(with: "user")))
    }
}
#endif

@available(iOS 13.0.0, *)
class SwiftUIViewModel: ObservableObject {
    let disposes: ListeningDisposeStore = ListeningDisposeStore()
    @Published var name: String?
    @Published var birthdate: String?
    @Published var image: UIImage?

    private let user: User1

    init(_ user: User1) {
        self.user = user
        user.name.flatMap().bind(toWeak: self, \.name).add(to: disposes)
        user.birthdate.flatMap({ $0.description }).bind(toWeak: self, \.birthdate).add(to: disposes)
        user.photo.flatMap().bind(toWeak: self, \.image).add(to: disposes)
    }

    func load() -> AnyListenable<(Void, Void)> {
        return AnyListenable(
            user.load().completion
                .combine(with: user.photo.load().completion)
        )
    }
}

class User1: Object {
    lazy var name: ReadonlyProperty<String> = l().property(in: self)
    lazy var birthdate: ReadonlyProperty<Date> = l().date(in: self)
    lazy var photo: ReadonlyFile<UIImage> = l().readonlyJpeg(in: self)

    override class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "name": return \User1.name
        case "birthdate": return \User1.birthdate
        case "photo": return \User1.photo
        default: return nil
        }
    }
}

@available(iOS 13.0.0, *)
struct ActivityIndicator: UIViewRepresentable {
    @Binding var isAnimating: Bool
    let style: UIActivityIndicatorView.Style

    func makeUIView(context: UIViewRepresentableContext<ActivityIndicator>) -> UIActivityIndicatorView {
        return UIActivityIndicatorView(style: style)
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: UIViewRepresentableContext<ActivityIndicator>) {
        isAnimating ? uiView.startAnimating() : uiView.stopAnimating()
    }
}

extension Property {
    @available(iOS 13.0, *)
    func binding() -> Binding<T?> {
        return Binding(
            get: { [unowned self] in self.wrappedValue },
            set: { [unowned self] in self.wrappedValue = $0 }
        )
    }
}
@available(iOS 13.0, *)
extension Publisher {
    func bind<T>(
        to obj: T, _ keyPath: WritableKeyPath<T, Output>,
        onCompletion: @escaping (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
        var object = obj
        return sink(
            receiveCompletion: onCompletion,
            receiveValue: { (v) in
                object[keyPath: keyPath] = v
            }
        )
    }
    func bind<T: AnyObject>(
        toWeak obj: T, _ keyPath: WritableKeyPath<T, Output>,
        onCompletion: @escaping (Subscribers.Completion<Failure>) -> Void) -> Disposable {
        return sink(
            receiveCompletion: onCompletion,
            receiveValue: { [weak obj] (v) in
                obj?[keyPath: keyPath] = v
            }
        )
    }
    func bind<T: AnyObject>(
        toUnowned obj: T, _ keyPath: ReferenceWritableKeyPath<T, Output>,
        onCompletion: @escaping (Subscribers.Completion<Failure>) -> Void) -> Disposable {
        return sink(
            receiveCompletion: onCompletion,
            receiveValue: { [unowned obj] (v) in
                obj[keyPath: keyPath] = v
            }
        )
    }
}

@available(iOS 13.0, *)
extension AnyCancellable {
    func add(to container: inout [AnyCancellable]) {
        container.append(self)
    }
    func add(to store: ListeningDisposeStore) {
        store.add(self)
    }
}
#endif
