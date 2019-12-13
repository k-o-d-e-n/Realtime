//
//  Listenable+UI.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 10/10/2017.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

// MARK: System type extensions

import Foundation

public struct RTime<Base> {
    public let base: Base
}

public protocol RealtimeListener {
    associatedtype Listened
    func take(realtime value: Listened)
}
public extension Listenable {
    func bind<RL: RealtimeListener>(to listener: RL) -> Disposable where RL.Listened == Out {
        return listening(onValue: listener.take)
    }
    func bind<RL: RealtimeListener & AnyObject>(toWeak listener: RL) -> Disposable where RL.Listened == Out {
        return listening(onValue: { [weak listener] next in
            listener?.take(realtime: next)
        })
    }
    func bind<RL: RealtimeListener & AnyObject>(toUnowned listener: RL) -> Disposable where RL.Listened == Out {
        return listening(onValue: { [unowned listener] next in
            listener.take(realtime: next)
        })
    }
}
extension Property: RealtimeListener {
    public func take(realtime value: T) {
        self <== value
    }
}

public protocol RealtimeCompatible {
    associatedtype Current = Self
    var realtime: RTime<Current> { get }
}
public extension RealtimeCompatible {
    var realtime: RTime<Self> { return RTime(base: self) }
}

/// Function for any lazy properties with completion handler calling on load.
/// Using: lazy var someProp: Type = onLoad(Type()) { loadedLazyProp in
///		/// action on loadedLazyProp
/// }
///
public func onLoad<V>(_ value: V, _ completion: (V) -> Void) -> V {
    defer { completion(value) }
    return value
}

/// Internal protocol
public protocol _Optional: ExpressibleByNilLiteral {
    associatedtype Wrapped
    func map<U>(_ f: (Wrapped) throws -> U) rethrows -> U?
    func flatMap<U>(_ f: (Wrapped) throws -> U?) rethrows -> U?

    var unsafelyUnwrapped: Wrapped { get }
    var wrapped: Wrapped? { get }
}
extension Optional: _Optional {
    public var wrapped: Wrapped? { return self }
}

public extension Listenable {
    func bind<T>(to property: Property<T>) -> Disposable where T == Out {
        return listening(onValue: { value in
            property <== value
        })
    }
    func bind<T>(to obj: T, _ keyPath: WritableKeyPath<T, Out>, onError: ((Error) -> Void)? = nil) -> Disposable {
        var object = obj
        return listening({ (state) in
            switch state {
            case .value(let v): object[keyPath: keyPath] = v
            case .error(let e): onError?(e)
            }
        })
    }
    func bind<T: AnyObject>(toWeak obj: T, _ keyPath: WritableKeyPath<T, Out>, onError: ((Error) -> Void)? = nil) -> Disposable {
        return listening({ [weak obj] (state) in
            switch state {
            case .value(let v): obj?[keyPath: keyPath] = v
            case .error(let e): onError?(e)
            }
        })
    }
    func bind<T: AnyObject>(toUnowned obj: T, _ keyPath: ReferenceWritableKeyPath<T, Out>, onError: ((Error) -> Void)? = nil) -> Disposable {
        return listening({ [unowned obj] (state) in
            switch state {
            case .value(let v): obj[keyPath: keyPath] = v
            case .error(let e): onError?(e)
            }
        })
    }
}

#if os(macOS) || os(iOS)

public extension RTime where Base: URLSession {
    func dataTask(for request: URLRequest) -> DataTask {
        return DataTask(session: base, request: request)
    }
    func dataTask(for url: URL) -> DataTask {
        return dataTask(for: URLRequest(url: url))
    }

    func repeatedDataTask(for request: URLRequest) -> RepeatedDataTask {
        return RepeatedDataTask(session: base, request: request)
    }
    func repeatedDataTask(for url: URL) -> RepeatedDataTask {
        return RepeatedDataTask(session: base, request: URLRequest(url: url))
    }

    struct DataTask: Listenable {
        var session: URLSession
        let task: URLSessionDataTask
        let storage: ValueStorage<(Data?, URLResponse?)>

        init(session: URLSession, request: URLRequest, storage: ValueStorage<(Data?, URLResponse?)> = .unsafe(strong: (nil, nil), repeater: .unsafe())) {
            precondition(storage.repeater != nil, "Storage must have repeater")
            self.session = session
            self.task = session.dataTask(for: request, storage: storage)
            self.storage = storage
        }

        public func listening(_ assign: Closure<ListenEvent<(Data?, URLResponse?)>, Void>) -> Disposable {
            task.resume()
            return storage.repeater!.listening(assign)
        }
    }

    final class RepeatedDataTask {
        var session: URLSession
        let request: URLRequest
        var task: URLSessionDataTask
        let repeater: Repeater<(Data?, URLResponse?)>

        init(session: URLSession, request: URLRequest, repeater: Repeater<(Data?, URLResponse?)> = .unsafe()) {
            self.session = session
            self.request = request
            self.task = session.dataTask(for: request, repeater: repeater)
            self.repeater = repeater
        }

        public func listening(_ assign: Closure<ListenEvent<(Data?, URLResponse?)>, Void>) -> Disposable {
            task.resume()
            return repeater.listening(assign)
        }
    }
}
extension URLSessionTask {
    var isInvalidated: Bool {
        switch state {
        case .canceling, .completed: return true
        case .running, .suspended: return false
        }
    }
}
extension URLSession: RealtimeCompatible {
    fileprivate func dataTask(for request: URLRequest, storage: ValueStorage<(Data?, URLResponse?)>) -> URLSessionDataTask {
        return dataTask(with: request) { (data, response, error) in
            if let e = error {
                storage.sendError(e)
            } else {
                storage.value = (data, response)
            }
        }
    }

    fileprivate func dataTask(for request: URLRequest, repeater: Repeater<(Data?, URLResponse?)>) -> URLSessionDataTask {
        return dataTask(with: request) { (data, response, error) in
            if let e = error {
                repeater.send(.error(e))
            } else {
                repeater.send(.value((data, response)))
            }
        }
    }
}
#endif

// MARK: - UI

#if os(iOS)
import UIKit

public extension Listenable where Self.Out == String? {
    func bind(to label: UILabel, default def: String? = nil) -> Disposable {
        return listening(onValue: .weak(label) { data, l in l?.text = data ?? def })
    }
    func bind(to label: UILabel, default def: String? = nil, didSet: @escaping (UILabel, Out) -> Void) -> Disposable {
        return listening(onValue: .weak(label) { data, l in
            l.map { $0.text = data ?? def; didSet($0, data) }
        })
    }
    func bindWithUpdateLayout(to label: UILabel) -> Disposable {
        return bind(to: label, didSet: { v, _ in v.superview?.setNeedsLayout() })
    }
    func bind(to label: UITextField, default def: String? = nil) -> Disposable {
        return listening(onValue: .weak(label) { data, l in l?.text = data ?? def })
    }
    func bind(to label: UITextField, default def: String? = nil, didSet: @escaping (UITextField, Out) -> Void) -> Disposable {
        return listening(onValue: .weak(label) { data, l in
            l.map { $0.text = data ?? def; didSet($0, data) }
        })
    }
}
public extension Listenable where Self.Out == String {
    func bind(to label: UILabel) -> Disposable {
        return listening(onValue: .weak(label) { data, l in l?.text = data })
    }
}
public extension Listenable where Self.Out == UIImage? {
    func bind(to imageView: UIImageView, default def: UIImage? = nil) -> Disposable {
        return listening(onValue: .weak(imageView) { data, iv in iv?.image = data ?? def })
    }
}

public struct ControlEvent<C: UIControl>: Listenable {
    unowned var control: C
    let events: UIControl.Event

    public func listening(_ assign: Assign<ListenEvent<(control: C, event: UIEvent)>>) -> Disposable {
        let controlListening = UIControl.Listening<C>(control, events: events, assign: assign)
        defer {
            controlListening.onStart()
        }
        return controlListening
    }
}

extension UIControl {
    fileprivate class Listening<C: UIControl>: Disposable, Hashable {
        weak var control: C?
        let events: UIControl.Event
        let assign: Assign<ListenEvent<(control: C, event: UIEvent)>>

        init(_ control: C, events: UIControl.Event, assign: Assign<ListenEvent<(control: C, event: UIEvent)>>) {
            self.control = control
            self.events = events
            self.assign = assign
        }

        @objc func onEvent(_ control: UIControl, _ event: UIEvent) {
            assign.assign(.value((unsafeDowncast(control, to: C.self), event)))
        }

        func onStart() {
            control?.addTarget(self, action: #selector(onEvent(_:_:)), for: events)
        }

        func onStop() {
            control?.removeTarget(self, action: #selector(onEvent(_:_:)), for: events)
        }

        func dispose() {
            onStop()
        }

        public func hash(into hasher: inout Hasher) { hasher.combine(events.rawValue) }
        static func ==(lhs: Listening, rhs: Listening) -> Bool { return lhs === rhs }
    }
}
extension UIControl: RealtimeCompatible {}
public extension RTime where Base: UIControl {
    func onEvent(_ controlEvent: UIControl.Event) -> ControlEvent<Base> {
        return ControlEvent(control: base, events: controlEvent)
    }
}
public extension RTime where Base: UITextField {
    var text: Preprocessor<ControlEvent<Base>, String?> {
        return onEvent(.editingChanged).map { $0.0.text }
    }
}

extension UIBarButtonItem {
    public class Tap<BI: UIBarButtonItem>: Listenable {
        let repeater: Repeater<BI> = Repeater.unsafe()
        weak var buttonItem: BI?

        init(item: BI) {
            self.buttonItem = item
            item.target = self
            item.action = #selector(_action(_:))
        }

        @objc func _action(_ button: UIBarButtonItem) {
            repeater.send(.value(button as! BI))
        }

        public func listening(_ assign: Closure<ListenEvent<BI>, Void>) -> Disposable {
            let disposable = repeater.listening(assign)
            let unmanaged = Unmanaged.passUnretained(self).retain()
            return ListeningDispose.init({
                unmanaged.release()
                disposable.dispose()
            })
        }
    }
}
extension UIBarButtonItem: RealtimeCompatible {}
extension RTime where Base: UIBarButtonItem {
    public var tap: UIBarButtonItem.Tap<Base> { return UIBarButtonItem.Tap(item: base) }
}

public extension RTime where Base: UIImagePickerController {
    @available(iOS 9.0, *)
    var image: UIImagePickerController.ImagePicker {
        return UIImagePickerController.ImagePicker(controller: base)
    }
}
extension UIImagePickerController: RealtimeCompatible {
    @available (iOS 9.0, *)
    public struct ImagePicker: Listenable {
        unowned var controller: UIImagePickerController

        public typealias Out = (UIImagePickerController, [UIImagePickerController.InfoKey : Any])

        public func listening(_ assign: Assign<ListenEvent<Out>>) -> Disposable {
            let listening = Listening(controller, assign: assign)
            defer {
                listening.start()
            }
            return listening
        }
    }
    @available (iOS 9.0, *)
    fileprivate class Listening: NSObject, Disposable, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var _isDisposed: Bool = false
        unowned let controller: UIImagePickerController
        let assign: Assign<ListenEvent<Out>>

        typealias Out = (UIImagePickerController, [UIImagePickerController.InfoKey : Any])

        init(_ controller: UIImagePickerController, assign: Assign<ListenEvent<Out>>) {
            self.controller = controller
            self.assign = assign
        }

        deinit {
            dispose()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            assign.call(.value((picker, info)))
            dispose()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            assign.call(.error(NSError(domain: "imagePicker.cancel", code: 0, userInfo: nil)))
            dispose()
        }

        func start() {
            guard !_isDisposed else { return }
            controller.delegate = self
        }

        func stop() {
            guard !_isDisposed else { return }
            controller.delegate = nil
        }

        func dispose() {
            guard !_isDisposed else {
                return
            }
            _isDisposed = true
            controller.delegate = nil
            guard controller.viewIfLoaded?.window != nil else {
                return
            }

            controller.dismiss(animated: true, completion: nil)
        }
    }
}
#endif

#if canImport(Combine)
import Combine

@available(iOS 13.0, macOS 10.15, *)
extension Cancellable where Self: Disposable {
    public func cancel() { dispose() }
}

@available(iOS 13.0, macOS 10.15, *)
extension AnyCancellable: Disposable {
    public func dispose() { cancel() }
}

@available(iOS 13.0, macOS 10.15, *)
extension Publisher where Self: Listenable, Output == Out {
    public func listening(_ assign: Assign<ListenEvent<Out>>) -> Disposable {
        return sink(
            receiveCompletion: { (completion) in
                if case .failure(let err) = completion {
                    assign.call(.error(err))
                }
            },
            receiveValue: { (out) in
                assign.call(.value(out))
            }
        )
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension ListeningDispose: Subscription {
    public var combineIdentifier: CombineIdentifier { return CombineIdentifier(self) }
    public func request(_ demand: Subscribers.Demand) {}
}

@available(iOS 13.0, macOS 10.15, *)
extension Listenable where Self: Publisher, Out == Output, Failure == Error {
    public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
        let dispose = listening({ (event) in
            switch event {
            case .value(let v):
                _ = subscriber.receive(v)
            case .error(let e): subscriber.receive(completion: .failure(e))
            }
        })
        subscriber.receive(subscription: ListeningDispose(dispose))
    }
}

extension AnyListenable: Publisher {
    public typealias Output = Out
    public typealias Failure = Error
}
extension Repeater: Publisher {
    public typealias Output = T
    public typealias Failure = Error
}
//extension ValueStorage: Publisher {
//    public typealias Output = T
//    public typealias Failure = Error
//}
extension Constant: Publisher {
    public typealias Output = T
    public typealias Failure = Error
}
extension SequenceListenable: Publisher {
    public typealias Output = Element
    public typealias Failure = Error
}
extension ReadonlyProperty: Publisher {
    public typealias Output = PropertyState<T>
    public typealias Failure = Error
}
#endif
