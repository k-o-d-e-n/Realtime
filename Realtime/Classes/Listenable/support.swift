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
/// Using: lazy var someProp: Type = didLoad(Type()) { loadedLazyProp in
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
    func loadOnReceive() -> OwnedOnReceivePreprocessor<OutData, OutData> {
        return onReceive({ (v, p) in
            v.load(completion: .just { _ in p.fulfill() })
        })
    }
}

public extension Listenable {
    func asyncMap<U: RealtimeValueActions>(_ transform: @escaping (OutData) -> U) -> OwnedOnReceivePreprocessor<OutData, U> {
        return map(transform).onReceive({ (v, p) in
            v.load(completion: .just { _ in p.fulfill() })
        })
    }
    func loadRelated<Loaded: RealtimeValueActions>(_ transform: @escaping (OutData) -> Loaded?) -> OwnedOnReceivePreprocessor<OutData, OutData> {
        return onReceive({ (v, p) in
            transform(v)?.load(completion: .just { _ in p.fulfill() })
        })
    }
}

public extension Listenable where OutData: _Optional {
	/// skips nil values
    func flatMap<U>(_ transform: @escaping (OutData.Wrapped) -> U) -> OwnedTransformedFilteredPreprocessor<OutData, U> {
        return self
            .filter { $0.map { _ in true } ?? false }
            .map { transform($0.unsafelyUnwrapped) }
    }
    func asyncFlatMap<U: RealtimeValueActions>(_ transform: @escaping (OutData.Wrapped) -> U) -> OwnedOnReceivePreprocessor<OutData, U> {
        return flatMap(transform).onReceive({ (v, p) in
            v.load(completion: .just { _ in p.fulfill() })
        })
    }
}

// MARK: - UI

public extension Listenable where Self.OutData == String? {
    func bind(to label: UILabel) -> ListeningItem {
        return listeningItem(.weak(label) { data, l in l?.text = data })
    }
    func bind(to label: UILabel, didSet: @escaping (UILabel, OutData) -> Void) -> ListeningItem {
        return listeningItem(.weak(label) { data, l in
            l.map { $0.text = data; didSet($0, data) }
        })
    }
    func bindWithUpdateLayout(to label: UILabel) -> ListeningItem {
        return bind(to: label, didSet: { v, _ in v.superview?.setNeedsLayout() })
    }
}
public extension Listenable where Self.OutData == String {
    func bind(to label: UILabel) -> ListeningItem {
        return listeningItem(.weak(label) { data, l in l?.text = data })
    }
}
public extension Listenable where Self.OutData == UIImage? {
    func bind(to imageView: UIImageView) -> ListeningItem {
        return listeningItem(.weak(imageView) { data, iv in iv?.image = data })
    }
}

extension UIControl: Listenable {
    public typealias OutData = Void

    private func makeDispose(for events: UIControlEvents, listening: AnyListening) -> Disposable {
        return ControlListening(self, events: events, listening: listening)
    }
    private func makeListeningItem(for events: UIControlEvents, listening: AnyListening) -> ListeningItem {
        let controlListening = ControlListening(self, events: events, listening: listening)
        return ListeningItem(start: controlListening.onStart,
                             stop: controlListening.onStop,
                             notify: controlListening.sendData,
                             token: ())
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<Void>) -> Disposable {
        return makeDispose(for: .allEvents, listening: config(Listening(bridge: assign.assign)))
    }

    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<Void>) -> ListeningItem {
        return makeListeningItem(for: .allEvents, listening: config(Listening(bridge: assign.assign)))
    }

    public func listening(as config: (AnyListening) -> AnyListening = { $0 }, events: UIControlEvents, _ assign: Assign<Void>) -> Disposable {
        return makeDispose(for: events, listening: config(Listening(bridge: assign.assign)))
    }

    public func listeningItem(as config: (AnyListening) -> AnyListening = { $0 }, events: UIControlEvents, _ assign: Assign<Void>) -> ListeningItem {
        return makeListeningItem(for: events, listening: config(Listening(bridge: assign.assign)))
    }

    private class ControlListening: AnyListening, Disposable, Hashable {
        unowned let control: UIControl
        let events: UIControlEvents
        let base: AnyListening

        var isInvalidated: Bool { return control.allTargets.contains(self) }
        var dispose: () -> Void { return onStop }

        init(_ control: UIControl, events: UIControlEvents, listening: AnyListening) {
            self.control = control
            self.events = events
            self.base = listening

            onStart()
        }

        @objc func onEvent(_ control: UIControl, _ event: UIEvent) { // TODO: UIEvent
            sendData()
        }

        func sendData() {
            base.sendData()
        }

        func onStart() {
            control.addTarget(self, action: #selector(onEvent(_:_:)), for: events)
        }

        func onStop() {
            control.removeTarget(self, action: #selector(onEvent(_:_:)), for: events)
            base.onStop()
        }

        var hashValue: Int { return Int(events.rawValue) }
        static func ==(lhs: ControlListening, rhs: ControlListening) -> Bool {
            return lhs === rhs
        }
    }
}

//// MARK: Attempts

import UIKit

extension UITextField {
    class Realtime {
        private weak var base: UIKit.UITextField!

        init(base: UIKit.UITextField) {
            self.base = base
        }

        lazy var text: Property<String?> = Property(PropertyValue(unowned: self.base, getter: { $0.text }, setter: { $0.text = $1 }))
        lazy var state: Property<String?> = {
            let propertyValue = PropertyValue<String?>(unowned: self.base, getter: { $0.text }, setter: { $0.text = $1 })
            self.base.addTarget(self, action: #selector(self.textDidChange), for: .valueChanged)
            return Property(propertyValue)
        }()

        @objc private func textDidChange() {
            state.value = self.base.text
        }
    }
}
