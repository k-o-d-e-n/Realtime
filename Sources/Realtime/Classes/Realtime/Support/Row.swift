//
//  Row.swift
//  Pods
//
//  Created by Denis Koryttsev on 09.06.2021.
//

import Foundation
#if COMBINE && canImport(Combine)
import Combine
/// #elseif REALTIME && canImport(Realtime)
/// import Realtime
#endif

#if os(iOS) || os(tvOS)

public enum RowViewBuilder<View> {
    case reuseIdentifier(String)
    case `static`(View)
    case custom((UITableView, IndexPath) -> View)
}

struct RowState: OptionSet {
    let rawValue: CShort

    init(rawValue: CShort) {
        self.rawValue = rawValue
    }
}
extension RowState {
    static let free: RowState = RowState(rawValue: 1 << 0)
    static let displaying: RowState = RowState(rawValue: 1 << 1)
    static let pending: RowState = RowState(rawValue: 1 << 2)
    static let removed: RowState = RowState(rawValue: 1 << 3)
}

// TODO: It seems we can get rid of Model at all, by passing model just to closure
@dynamicMemberLookup
open class Row<View: AnyObject, Model: AnyObject>: ReuseItem<View> {
    public typealias UpdateEvent = (view: View, model: Model) // TODO: May be it is reasonable to add Self
    public typealias DidSelectEvent = (form: Form<Model>, indexPath: IndexPath)
    #if COMBINE
    var internalDispose: [AnyCancellable] = []
    #else
    var internalDispose: [Disposable] = []
    #endif
    #if COMBINE
    lazy var _update: PassthroughSubject<UpdateEvent, Never> = PassthroughSubject()
    fileprivate lazy var _didSelect: PassthroughSubject<DidSelectEvent, Never> = PassthroughSubject()
    #else
    lazy var _update: Repeater<UpdateEvent> = .unsafe()
    fileprivate lazy var _didSelect: Repeater<DidSelectEvent> = .unsafe()
    #endif

    var dynamicValues: [String: Any] = [:]
    var state: RowState = [.free, .pending]
    open var indexPath: IndexPath?

    open internal(set) weak var model: Model?

    let viewBuilder: RowViewBuilder<View>

    public required init(viewBuilder: RowViewBuilder<View>) {
        self.viewBuilder = viewBuilder
    }
    deinit {}

    public convenience init(reuseIdentifier: String) {
        self.init(viewBuilder: .reuseIdentifier(reuseIdentifier))
    }

    open subscript<T>(dynamicMember member: String) -> T? {
        set { dynamicValues[member] = newValue }
        get { return dynamicValues[member] as? T }
    }

    #if COMBINE
    public func updatePublisher() -> AnyPublisher<(UpdateEvent, Row<View, Model>), Never> {
        _update.compactMap({ [weak self] event -> (UpdateEvent, Row<View, Model>)? in
            guard let `self` = self else { return nil }
            return (event, self)
        }).eraseToAnyPublisher()
    }
    #else
    public func mapUpdate() -> AnyListenable<(UpdateEvent, Row<View, Model>)> {
        AnyListenable(_update.compactMap({ [weak self] event -> (UpdateEvent, Row<View, Model>)? in
            guard let `self` = self else { return nil }
            return (event, self)
        }))
    }
    #endif

    open func onUpdate(_ doit: @escaping ((view: View, model: Model), Row<View, Model>) -> Void) {
        #if COMBINE
        _update.sink(receiveValue: { [unowned self] in doit($0, self) }).store(in: &internalDispose)
        #else
        _update.listening(onValue: Closure.guarded(self, assign: doit)).add(to: &internalDispose)
        #endif
    }

    #if COMBINE
    public func selectPublisher() -> AnyPublisher<(DidSelectEvent, Row<View, Model>), Never> {
        _didSelect.compactMap({ [weak self] event -> (DidSelectEvent, Row<View, Model>)? in
            guard let `self` = self else { return nil }
            return (event, self)
        }).eraseToAnyPublisher()
    }
    #else
    public func mapSelect() -> AnyListenable<(DidSelectEvent, Row<View, Model>)> {
        AnyListenable(_didSelect.compactMap({ [weak self] event -> (DidSelectEvent, Row<View, Model>)? in
            guard let `self` = self else { return nil }
            return (event, self)
        }))
    }
    #endif

    open func onSelect(_ doit: @escaping (DidSelectEvent, Row<View, Model>) -> Void) {
        #if COMBINE
        _didSelect.sink(receiveValue: { [unowned self] in doit($0, self) }).store(in: &internalDispose)
        #else
        _didSelect.listening(onValue: Closure.guarded(self, assign: doit)).add(to: &internalDispose)
        #endif
    }

    open func didSelect(_ form: Form<Model>, didSelectRowAt indexPath: IndexPath) {
        #if COMBINE
        _didSelect.send((form, indexPath))
        #else
        _didSelect.send(.value((form, indexPath)))
        #endif
    }

    override func free() {
        super.free()
        model = nil
    }

    public func sendSelectEvent(_ form: Form<Model>, at indexPath: IndexPath) {
        #if COMBINE
        _didSelect.send((form, indexPath))
        #else
        _didSelect.send((form, indexPath))
        #endif
    }

    public func removeAllDynamicValues() {
        dynamicValues.removeAll()
    }
}
extension Row where View: UITableViewCell {
    public convenience init(static view: View) {
        self.init(viewBuilder: .static(view))
    }
    internal func buildCell(for tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        switch viewBuilder {
        case .reuseIdentifier(let identifier):
            return tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        case .static(let cell): return cell
        case .custom(let closure): return closure(tableView, indexPath)
        }
    }
}
public extension Row where View: UIView {
    var isVisible: Bool {
        return state.contains(.displaying) && super._isVisible
    }
    internal func build(for tableView: UITableView, at section: Int) -> UIView? {
        switch viewBuilder {
        case .reuseIdentifier(let identifier):
            return tableView.dequeueReusableHeaderFooterView(withIdentifier: identifier)
        case .static(let view): return view
        case .custom(let closure): return closure(tableView, IndexPath(row: 0, section: 0))
        }
    }
}
extension Row: CustomDebugStringConvertible {
    public var debugDescription: String {
        return """
        \(type(of: self)): \(withUnsafePointer(to: self, String.init(describing:))) {
            view: \(view as Any),
            model: \(model as Any),
            state: \(state),
            values: \(dynamicValues)
        }
        """
    }
}
extension Row {
    func willDisplay(with view: View, model: Model, indexPath: IndexPath) {
        if !state.contains(.displaying) || self.view !== view {
            self.indexPath = indexPath
            self.view = view
            self.model = model
            state.insert(.displaying)
            state.remove(.free)
            _update.send((view, model))
        }
    }
    func didEndDisplay(with view: View, indexPath: IndexPath) {
        if !state.contains(.free) && self.view === view {
            self.indexPath = nil
            state.remove(.displaying)
            free()
            state.insert([.pending, .free])
        } else {
            /// debugLog("\(row.state) \n \(row.view as Any) \n\(cell)")
        }
    }
}

#endif
