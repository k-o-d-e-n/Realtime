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

public struct ControlEvent: Listenable {
    unowned var control: UIControl
    let event: UIControlEvents

    public func listening(_ assign: Assign<(UIControl, UIEvent)>) -> Disposable {
        return control.listen(for: event, assign)
    }

    public func listeningItem(_ assign: Assign<(UIControl, UIEvent)>) -> ListeningItem {
        return control.listenItem(for: event, assign)
    }
}

public extension Listenable where Self: UIControl {
    func onEvent(_ controlEvent: UIControlEvents) -> ControlEvent {
        return ControlEvent(control: self, event: controlEvent)
    }
}

extension UIControl: Listenable {
    public func listening(_ assign: Assign<(UIControl, UIEvent)>) -> Disposable {
        return listen(for: .allEvents, assign)
    }

    public func listeningItem(_ assign: Assign<(UIControl, UIEvent)>) -> ListeningItem {
        return listenItem(for: .allEvents, assign)
    }

    fileprivate func listen(for events: UIControlEvents, _ assign: Assign<(UIControl, UIEvent)>) -> ControlListening {
        let controlListening = ControlListening(self, events: events, assign: assign)
        defer {
            controlListening.onStart()
        }
        return controlListening
    }
    fileprivate func listenItem(for events: UIControlEvents, _ assign: Assign<(UIControl, UIEvent)>) -> ListeningItem {
        var event: UIEvent = UIEvent()
        let controlListening = ControlListening(self, events: events, assign: assign.with(work: { (_, e) in
            event = e
        }))
        defer {
            controlListening.onStart()
        }
        return ListeningItem(start: controlListening.onStart,
                             stop: controlListening.onStop,
                             notify: { [unowned self] in assign.assign((self, event)) },
                             token: ())
    }

    fileprivate class ControlListening: Disposable, Hashable {
        unowned let control: UIControl
        let events: UIControlEvents
        let assign: Assign<(UIControl, UIEvent)>

        var isInvalidated: Bool { return control.allTargets.contains(self) }
        var dispose: () -> Void { return onStop }

        init(_ control: UIControl, events: UIControlEvents, assign: Assign<(UIControl, UIEvent)>) {
            self.control = control
            self.events = events
            self.assign = assign
        }

        @objc func onEvent(_ control: UIControl, _ event: UIEvent) {
            assign.assign((control, event))
        }

        func onStart() {
            control.addTarget(self, action: #selector(onEvent(_:_:)), for: events)
        }

        func onStop() {
            control.removeTarget(self, action: #selector(onEvent(_:_:)), for: events)
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
