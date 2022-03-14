//
//  ReusableItem.swift
//  Pods
//
//  Created by Denis Koryttsev on 09.06.2021.
//

#if COMBINE && canImport(Combine)
import Combine
#endif
#if canImport(Realtime)
import Realtime
#endif

protocol ReuseItemProtocol {
    func free()
}

open class ReuseItem<View: AnyObject>: ReuseItemProtocol {
    #if COMBINE && canImport(Combine)
    public var disposeStorage: [AnyCancellable] = [] // TODO: Rename `disposeStorage`
    #elseif REALTIME_UI
    public var disposeStorage: [Disposable] = []
    #endif

    open internal(set) weak var view: View?

    public init() {}
    deinit { free() }

    func free() {
        #if COMBINE && canImport(Combine)
        disposeStorage.removeAll()
        #elseif REALTIME_UI
        disposeStorage.forEach({ $0.dispose() })
        disposeStorage.removeAll()
        #endif
        view = nil
    }
}

#if os(iOS) || os(tvOS)
extension ReuseItem where View: UIView {
    var _isVisible: Bool { return view.map { !$0.isHidden && $0.window != nil } ?? false }
}
#endif
