//
//  Listenable+UI.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 10/10/2017.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import UIKit

public protocol _Optional {
    associatedtype Wrapped
    func map<U>(_ f: (Wrapped) throws -> U) rethrows -> U?
    func flatMap<U>(_ f: (Wrapped) throws -> U?) rethrows -> U?
    var isNone: Bool { get }
    var isSome: Bool { get }
    var unsafelyUnwrapped: Wrapped { get }
}
extension Optional: _Optional {
    public var isNone: Bool {
        if case .none = self { return true }
        return false
    }
    public var isSome: Bool {
        if case .some = self { return true }
        return false
    }
}

public extension InsiderOwner where T: RealtimeValueActions {
    func loadOnReceive() -> OwnedOnReceivePreprocessor<Self, T, T> {
        return onReceive({ (v, p) in
            v.load(completion: { (_, _) in p.fulfill() })
        })
    }
}

public extension InsiderOwner {
    func asyncMap<U: RealtimeValueActions>(_ transform: @escaping (T) -> U) -> OwnedOnReceivePreprocessor<Self, U, U> {
        return map(transform).onReceive({ (v, p) in
            v.load(completion: { (_, _) in p.fulfill() })
        })
    }
    func loadRelated<Loaded: RealtimeValueActions>(_ transform: @escaping (T) -> Loaded?) -> OwnedOnReceivePreprocessor<Self, T, T> {
        return onReceive({ (v, p) in
            transform(v)?.load(completion: { (_, _) in p.fulfill() })
        })
    }
}

public extension InsiderOwner where T: _Optional {
    func flatMap<U>(_ transform: @escaping (T.Wrapped) -> U) -> OwnedTransformedFilteredPreprocessor<Self, T, U> {
        return filter { $0.isSome }.map { $0.unsafelyUnwrapped }.map(transform)
    }
    func asyncFlatMap<U: RealtimeValueActions>(_ transform: @escaping (T.Wrapped) -> U) -> OwnedOnReceivePreprocessor<Self, T, U> {
        return flatMap(transform).onReceive({ (v, p) in
            v.load(completion: { (_, _) in p.fulfill() })
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

//// MARK: Attempts

class ControlEventsTarget<Value>: Disposable, InsiderOwner {
    private var _dispose: (() -> Void)!
    var dispose: () -> Void { return _dispose }
    var insider: Insider<Value>

    init<Control: UIControl>(control: Control, events: UIControlEvents, getter: @escaping (Control?) -> Value) {
        self.insider = Insider(source: { [weak control] in getter(control) })
        self._dispose = { [weak self, weak control] in control?.removeTarget(self, action: nil, for: events) }
        control.addTarget(self, action: #selector(didReceiveEvent(_:)), for: events)
    }

    @objc func didReceiveEvent(_ control: UIControl) {
        insider.dataDidChange()
    }
}

struct Realtime<Base> {
    //    let base: Base
}

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

extension UITextField {
    // TODO: need decision without using layer as retainer Property struct.
    var realtimeText: Property<String?> {
        set { layer.setValue(newValue, forKey: "realtime.text") }
        get {
            guard layer.value(forKey: "realtime.text") != nil else {
                let propertyValue = PropertyValue<String?>(unowned: self, getter: { $0.text }, setter: { $0.text = $1 })
                addTarget(self, action: #selector(textDidChange), for: .valueChanged)
                self.realtimeText = Property(propertyValue)
                return self.realtimeText
            }

            return layer.value(forKey: "realtime.text") as! Property<String?>
        }
    }

    @objc private func textDidChange() {
        realtimeText.value = text
    }

    var rt: UITextField.Realtime {
        return .init(base: self)
    }

    var realtime: ControlEventsTarget<String?> {
        let target = Unmanaged.passRetained(ControlEventsTarget(control: self, events: .valueChanged, getter: { $0?.text }))
        return target.takeUnretainedValue()
    }

    var textInsider: Insider<String?> {
        set { }
        get { return Insider(source: { [weak self] in self?.text }) }
    }
    
}
