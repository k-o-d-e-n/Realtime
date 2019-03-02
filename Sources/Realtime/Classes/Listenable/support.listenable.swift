//
//  Listenable+UI.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 10/10/2017.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

// MARK: System type extensions

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

public extension Listenable where Out: RealtimeValueActions {
    /// Loads a value is associated with `RealtimeValueActions` value
    func load(timeout: DispatchTimeInterval = .seconds(10)) -> Preprocessor<Out, Out> {
        return doAsync({ (prop, promise) in
            prop.load(timeout: timeout, completion: <-{ err in
                if let e = err {
                    promise.reject(e)
                } else {
                    promise.fulfill()
                }
            })
        })
    }
}

public extension Listenable {
    func bind<T>(to property: Property<T>) -> Disposable where T == Out {
        return listening(onValue: { value in
            property <== value
        })
    }
}

// MARK: - UI

#if os(macOS)

public extension RTime where Base: URLSession {
    public func dataTask(for request: URLRequest) -> DataTask {
        return DataTask(session: base, request: request)
    }
    public func dataTask(for url: URL) -> DataTask {
        return dataTask(for: URLRequest(url: url))
    }

    public func repeatedDataTask(for request: URLRequest) -> RepeatedDataTask {
        return RepeatedDataTask(session: base, request: request)
    }
    public func repeatedDataTask(for url: URL) -> RepeatedDataTask {
        return RepeatedDataTask(session: base, request: URLRequest(url: url))
    }

    public struct DataTask: Listenable {
        var session: URLSession
        let task: URLSessionDataTask
        let storage: ValueStorage<(Data?, URLResponse?)>

        init(session: URLSession, request: URLRequest, storage: ValueStorage<(Data?, URLResponse?)> = .unsafe(strong: (nil, nil))) {
            self.session = session
            self.task = session.dataTask(for: request, storage: storage)
            self.storage = storage
        }

        public func listening(_ assign: Closure<ListenEvent<(Data?, URLResponse?)>, Void>) -> Disposable {
            task.resume()
            return storage.listening(assign)
        }

        public func listeningItem(_ assign: Closure<ListenEvent<(Data?, URLResponse?)>, Void>) -> ListeningItem {
            switch task.state {
            case .completed, .canceling:
                let value = self.storage.value
                let error = task.error
                return ListeningItem(
                    resume: { assign.call(error.map({ .error($0) }) ?? .value(value)) },
                    pause: {},
                    token: ()
                )
            default:
                task.resume()
                return storage.listeningItem(assign)
            }
        }
    }

    public final class RepeatedDataTask: Listenable {
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

        public func listeningItem(_ assign: Closure<ListenEvent<(Data?, URLResponse?)>, Void>) -> ListeningItem {
            restartIfNeeded()
            return ListeningItem(
                resume: { [weak self] () -> Void? in
                    return self?.restartIfNeeded()
                },
                pause: task.suspend,
                dispose: task.cancel,
                token: ()
            )
        }

        private func restartIfNeeded() {
            switch task.state {
            case .completed, .canceling:
                task = session.dataTask(for: request, repeater: repeater)
            default: break
            }
            task.resume()
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

import UIKit

public extension Listenable where Self.Out == String? {
    func bind(to label: UILabel, default def: String? = nil) -> ListeningItem {
        return listeningItem(onValue: .weak(label) { data, l in l?.text = data ?? def })
    }
    func bind(to label: UILabel, default def: String? = nil, didSet: @escaping (UILabel, Out) -> Void) -> ListeningItem {
        return listeningItem(onValue: .weak(label) { data, l in
            l.map { $0.text = data ?? def; didSet($0, data) }
        })
    }
    func bindWithUpdateLayout(to label: UILabel) -> ListeningItem {
        return bind(to: label, didSet: { v, _ in v.superview?.setNeedsLayout() })
    }
}
public extension Listenable where Self.Out == String {
    func bind(to label: UILabel) -> ListeningItem {
        return listeningItem(onValue: .weak(label) { data, l in l?.text = data })
    }
}
public extension Listenable where Self.Out == UIImage? {
    func bind(to imageView: UIImageView, default def: UIImage? = nil) -> ListeningItem {
        return listeningItem(onValue: .weak(imageView) { data, iv in iv?.image = data ?? def })
    }
}

public struct ControlEvent<C: UIControl>: Listenable {
    unowned var control: C
    let events: UIControlEvents

    public func listening(_ assign: Assign<ListenEvent<(control: C, event: UIEvent)>>) -> Disposable {
        let controlListening = UIControl.Listening<C>(control, events: events, assign: assign)
        defer {
            controlListening.onStart()
        }
        return controlListening
    }

    public func listeningItem(_ assign: Assign<ListenEvent<(control: C, event: UIEvent)>>) -> ListeningItem {
        let controlListening = UIControl.Listening<C>(control, events: events, assign: assign)
        defer {
            controlListening.onStart()
        }
        return ListeningItem(
            resume: controlListening.onStart,
            pause: controlListening.onStop,
            token: ()
        )
    }
}

extension UIControl {
    fileprivate class Listening<C: UIControl>: Disposable, Hashable {
        weak var control: C?
        let events: UIControlEvents
        let assign: Assign<ListenEvent<(control: C, event: UIEvent)>>

        init(_ control: C, events: UIControlEvents, assign: Assign<ListenEvent<(control: C, event: UIEvent)>>) {
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

        var hashValue: Int { return Int(events.rawValue) }
        static func ==(lhs: Listening, rhs: Listening) -> Bool {
            return lhs === rhs
        }
    }
}
extension UIControl: RealtimeCompatible {}
public extension RTime where Base: UIControl {
    func onEvent(_ controlEvent: UIControlEvents) -> ControlEvent<Base> {
        return ControlEvent(control: base, events: controlEvent)
    }
}
public extension RTime where Base: UITextField {
    var text: Preprocessor<(control: Base, event: UIEvent), String?> {
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
        public func listeningItem(_ assign: Closure<ListenEvent<BI>, Void>) -> ListeningItem {
            let item = repeater.listeningItem(assign)
            let unmanaged = Unmanaged.passUnretained(self).retain()
            return ListeningItem(
                resume: item.resume,
                pause: item.pause,
                dispose: { item.dispose(); unmanaged.release() },
                token: ()
            )
        }
    }
}
extension UIBarButtonItem: RealtimeCompatible {}
extension RTime where Base: UIBarButtonItem {
    public var tap: UIBarButtonItem.Tap<Base> { return UIBarButtonItem.Tap(item: base) }
}

public extension RTime where Base: UIImagePickerController {
    @available(iOS 9.0, *)
    public var image: UIImagePickerController.ImagePicker {
        return UIImagePickerController.ImagePicker(controller: base)
    }
}
extension UIImagePickerController: RealtimeCompatible {
    @available (iOS 9.0, *)
    public struct ImagePicker: Listenable {
        unowned var controller: UIImagePickerController

        public func listening(_ assign: Assign<ListenEvent<(UIImagePickerController, [String: Any])>>) -> Disposable {
            let listening = Listening(controller, assign: assign)
            defer {
                listening.start()
            }
            return listening
        }
        public func listeningItem(_ assign: Closure<ListenEvent<(UIImagePickerController, [String : Any])>, Void>) -> ListeningItem {
            let listening = Listening(controller, assign: assign)
            return ListeningItem(resume: listening.start, pause: listening.stop, dispose: listening.dispose, token: listening.start())
        }
    }
    @available (iOS 9.0, *)
    fileprivate class Listening: NSObject, Disposable, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var _isDisposed: Bool = false
        unowned let controller: UIImagePickerController
        let assign: Assign<ListenEvent<(UIImagePickerController, [String: Any])>>

        init(_ controller: UIImagePickerController, assign: Assign<ListenEvent<(UIImagePickerController, [String: Any])>>) {
            self.controller = controller
            self.assign = assign
        }

        deinit {
            dispose()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
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