//
//  Listenable+UI.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 10/10/2017.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import UIKit

internal func debugAction(_ action: () -> Void) {
    #if DEBUG
        action()
    #endif
}

internal func debugLog(_ message: String, _ file: String = #file, _ line: Int = #line) {
    debugAction {
        debugPrint("File: \(file)")
        debugPrint("Line: \(line)")
        debugPrint("Message: \(message)")
    }
}

internal func debugFatalError(condition: @autoclosure () -> Bool = true,
                              _ message: String = "", _ file: String = #file, _ line: Int = #line) {
    debugAction {
        if condition() {
            debugLog(message, file, line)
            if ProcessInfo.processInfo.arguments.contains("REALTIME_CRASH_ON_ERROR") {
                fatalError(message)
            }
        }
    }
}

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

// TODO: Add extension for all types with var asProperty, asRealtimeProperty
extension String {
    var asProperty: Property<String> { return Realtime.Property(value: self) }
}

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

public extension Listenable where OutData: RealtimeValueActions {
	/// adds loading action on receive new value
    func loadOnReceive() -> Preprocessor<OutData, OutData> {
        return onReceive({ (v, p) in
            v.load(completion: .just { _ in p.fulfill() })
        })
    }
}

public extension Listenable {
    func asyncMap<U: RealtimeValueActions>(_ transform: @escaping (OutData) -> U) -> Preprocessor<U, U> {
        return map(transform).onReceive({ (v, p) in
            v.load(completion: .just { _ in p.fulfill() })
        })
    }
    func loadRelated<Loaded: RealtimeValueActions>(_ transform: @escaping (OutData) -> Loaded?) -> Preprocessor<OutData, OutData> {
        return onReceive({ (v, p) in
            transform(v)?.load(completion: .just { _ in p.fulfill() })
        })
    }
}

public extension Listenable where OutData: _Optional {
	/// skips nil values
    func flatMap<U>(_ transform: @escaping (OutData.Wrapped) -> U) -> Preprocessor<OutData, U> {
        return self
            .filter { $0.map { _ in true } ?? false }
            .map { transform($0.unsafelyUnwrapped) }
    }
    func asyncFlatMap<U: RealtimeValueActions>(_ transform: @escaping (OutData.Wrapped) -> U) -> Preprocessor<U, U> {
        return flatMap(transform).onReceive({ (v, p) in
            v.load(completion: .just { _ in p.fulfill() })
        })
    }
}

// MARK: - UI

public extension Listenable where Self.OutData == String? {
    func bind(to label: UILabel) -> ListeningItem {
        return listeningItem(onValue: .weak(label) { data, l in l?.text = data })
    }
    func bind(to label: UILabel, didSet: @escaping (UILabel, OutData) -> Void) -> ListeningItem {
        return listeningItem(onValue: .weak(label) { data, l in
            l.map { $0.text = data; didSet($0, data) }
        })
    }
    func bindWithUpdateLayout(to label: UILabel) -> ListeningItem {
        return bind(to: label, didSet: { v, _ in v.superview?.setNeedsLayout() })
    }
}
public extension Listenable where Self.OutData == String {
    func bind(to label: UILabel) -> ListeningItem {
        return listeningItem(onValue: .weak(label) { data, l in l?.text = data })
    }
}
public extension Listenable where Self.OutData == UIImage? {
    func bind(to imageView: UIImageView) -> ListeningItem {
        return listeningItem(onValue: .weak(imageView) { data, iv in iv?.image = data })
    }
}

public struct ControlEvent<C: UIControl>: Listenable {
    unowned var control: C
    let events: UIControlEvents

    public func listening(_ assign: Assign<ListenEvent<(C, UIEvent)>>) -> Disposable {
        let controlListening = UIControl.Listening<C>(control, events: events, assign: assign)
        defer {
            controlListening.onStart()
        }
        return controlListening
    }

    public func listeningItem(_ assign: Assign<ListenEvent<(C, UIEvent)>>) -> ListeningItem {
        var event: UIEvent = UIEvent()
        let controlListening = UIControl.Listening<C>(control, events: events, assign: assign.with(work: { e in
            if let uiEvent = e.value?.1 {
                event = uiEvent
            }
        }))
        defer {
            controlListening.onStart()
        }
        return ListeningItem(start: controlListening.onStart,
                             stop: controlListening.onStop,
                             notify: { [unowned control] in assign.assign(.value((control, event))) },
                             token: ())
    }
}

extension UIControl {
    fileprivate class Listening<C: UIControl>: Disposable, Hashable {
        unowned let control: C
        let events: UIControlEvents
        let assign: Assign<ListenEvent<(C, UIEvent)>>

        var dispose: () -> Void { return onStop }

        init(_ control: C, events: UIControlEvents, assign: Assign<ListenEvent<(C, UIEvent)>>) {
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

        var hashValue: Int { return Int(events.rawValue) }
        static func ==(lhs: Listening, rhs: Listening) -> Bool {
            return lhs === rhs
        }
    }
}
public extension UIControl {
    func onEvent(_ controlEvent: UIControlEvents) -> ControlEvent<UIControl> {
        return ControlEvent(control: self, events: controlEvent)
    }
}
public extension UITextField {
    func onTextChange() -> Preprocessor<(UITextField, UIEvent), String?> {
        return ControlEvent(control: self, events: .valueChanged).map({ $0.0.text })
    }
}
