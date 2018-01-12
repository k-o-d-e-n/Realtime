//
//  Listenable+UI.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 10/10/2017.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import UIKit

extension InsiderAccessor where Self: ListeningMaker, Self.OutData == String? {
    func bind(to label: UILabel) -> ListeningItem {
        return listeningItem({ [weak label] data in label?.text = data })
    }
    func bind(to label: UILabel, didSet: @escaping (UILabel, OutData) -> Void) -> ListeningItem {
        return listeningItem({ [weak label] data in
            label.map { $0.text = data; didSet($0, data) }
        })
    }
    func bindWithUpdateLayout(to label: UILabel) -> ListeningItem {
        return bind(to: label, didSet: { v, _ in v.superview?.setNeedsLayout() })
    }
}
extension InsiderAccessor where Self: ListeningMaker, Self.OutData == String {
    func bind(to label: UILabel) -> ListeningItem {
        return listeningItem({ [weak label] data in label?.text = data })
    }
}
extension InsiderOwner where T == String? {
    func bind(to label: UILabel) -> ListeningItem {
        return listeningItem({ [weak label] data in label?.text = data })
    }
    func bind(to label: UILabel, didSet: @escaping (UILabel, T) -> Void) -> ListeningItem {
        return listeningItem({ [weak label] data in
            label.map { $0.text = data; didSet($0, data) }
        })
    }
    func bindWithUpdateLayout(to label: UILabel) -> ListeningItem {
        return bind(to: label, didSet: { v, _ in v.superview?.setNeedsLayout() })
    }
}
extension InsiderOwner where T == UIImage? {
    func bind(to imageView: UIImageView) -> ListeningItem {
        return listeningItem({ [weak imageView] data in imageView?.image = data })
    }
}
extension InsiderAccessor where Self: ListeningMaker, Self.OutData == UIImage? {
    func bind(to imageView: UIImageView) -> ListeningItem {
        return listeningItem({ [weak imageView] data in imageView?.image = data })
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
