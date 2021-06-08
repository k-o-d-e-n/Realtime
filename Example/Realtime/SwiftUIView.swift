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
    /// @ObservedObject var model: SwiftUIViewModel
    @ObservedObject var model: User1
    @State var loading: Bool = false
    var cancels: ListeningDisposeStore = ListeningDisposeStore()

    init(user: User1) {
        self.model = user
    }

    var body: some View {
        VStack {
            if !loading {
                Image(uiImage: model.photo ?? UIImage()).cornerRadius(10)
                TupleView(
                    (
                        Text("Name").italic(),
                        Text(model.name ?? "").bold()
                    )
                )
                TupleView(
                    (
                        Text("Birthdate").italic(),
                        Text(model.birthdate.mapValue(String.init(describing:)) ?? "").bold()
                    )
                )
            } else {
                ActivityIndicator(isAnimating: $loading, style: .large)
            }
        }.onAppear(perform: onAppear)
    }

    func onAppear() {
        _ = model.photo.load()
        _ = model.load()
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

protocol KotlinLike {}
extension KotlinLike {
    func `let`(_ completion: (Self) -> Void) -> Self {
        completion(self); return self
    }
}
extension _RealtimeValue: KotlinLike {}

@available(iOS 13.0, *)
class User1: Object, ObservableObject {
    let disposes: ListeningDisposeStore = ListeningDisposeStore()
    lazy var name: Property<String> = l().property(in: self).let { prop in
        /// make delay to prevent sent values immediatelly
        prop.delay(for: 0.1, scheduler: DispatchQueue.main).sink(receiveCompletion: {_ in}, receiveValue: { [weak self] _ in self?.objectWillChange.send() }).add(to: disposes)
    }
    lazy var birthdate: Property<Date> = l().date(in: self).let { prop in
        prop.delay(for: 0.1, scheduler: DispatchQueue.main).sink(receiveCompletion: {_ in}, receiveValue: { [weak self] _ in self?.objectWillChange.send() }).add(to: disposes)
    }
    lazy var photo: ReadonlyFile<UIImage> = l().readonlyJpeg(in: self).let { prop in
        prop.delay(for: 0.1, scheduler: DispatchQueue.main).sink(receiveCompletion: {_ in}, receiveValue: { [weak self] _ in self?.objectWillChange.send() }).add(to: disposes)
    }

    lazy var objectWillChange: ObservableObjectPublisher = ObservableObjectPublisher()
    /// lazy var objectWillChange: AnyPublisher<Void, Never> = photo.combineLatest(name, birthdate)
    ///    .mapError({ _ -> Never in fatalError() })
    ///    .map({ _ in () })
    ///    .eraseToAnyPublisher()

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
