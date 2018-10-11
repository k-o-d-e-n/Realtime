//
//  Listenable+UI.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 10/10/2017.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import UIKit

// MARK: System type extensions

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
    func load() -> Preprocessor<Out, Out> {
        return onReceive({ (prop, promise) in
            prop.load(completion: <-{ err in
                if let e = err {
                    promise.reject(e)
                } else {
                    promise.fulfill()
                }
            })
        })
    }
}

// MARK: - UI

public extension Listenable where Self.Out == String? {
    func bind(to label: UILabel) -> ListeningItem {
        return listeningItem(onValue: .weak(label) { data, l in l?.text = data })
    }
    func bind(to label: UILabel, didSet: @escaping (UILabel, Out) -> Void) -> ListeningItem {
        return listeningItem(onValue: .weak(label) { data, l in
            l.map { $0.text = data; didSet($0, data) }
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
    func bind(to imageView: UIImageView) -> ListeningItem {
        return listeningItem(onValue: .weak(imageView) { data, iv in iv?.image = data })
    }
}

public struct RTime<Base> {
    public let base: Base
}

public protocol RealtimeCompatible {
    associatedtype Current = Self
    var realtime: RTime<Current> { get }
}
public extension RealtimeCompatible {
    var realtime: RTime<Self> { return RTime(base: self) }
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
        unowned let control: C
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
            control.addTarget(self, action: #selector(onEvent(_:_:)), for: events)
        }

        func onStop() {
            control.removeTarget(self, action: #selector(onEvent(_:_:)), for: events)
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
public extension RTime where Base: UIControl {
    func onEvent(_ controlEvent: UIControlEvents) -> ControlEvent<Base> {
        return ControlEvent(control: base, events: controlEvent)
    }
}
extension UIControl: RealtimeCompatible {
    public func onEvent(_ controlEvent: UIControlEvents) -> ControlEvent<UIControl> {
        return ControlEvent(control: self, events: controlEvent)
    }
}
public extension RTime where Base: UITextField {
    var text: Preprocessor<(control: Base, event: UIEvent), String?> {
        return onEvent(.editingChanged).map { $0.0.text }
    }
}
public extension UITextField {
    func onTextChange() -> Preprocessor<(control: UITextField, event: UIEvent), String?> {
        return ControlEvent(control: self, events: .valueChanged).map({ $0.0.text })
    }
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
