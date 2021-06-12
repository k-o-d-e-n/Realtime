//
//  ReuseController.swift
//  Pods
//
//  Created by Denis Koryttsev on 11.06.2021.
//

#if os(iOS) || os(tvOS)

struct ReuseController<Row, Key: Hashable> where Row: ReuseItemProtocol {
    var freeItems: [Row] = []
    var activeItems: [Key: Row] = [:]

    typealias RowBuilder = () -> Row

    func active(at key: Key) -> Row? {
        return activeItems[key]
    }

    mutating func freeAll() {
        activeItems.forEach {
            $0.value.free()
            freeItems.append($0.value)
        }
        activeItems.removeAll()
    }

    mutating func free() {
        activeItems.forEach { $0.value.free() }
        activeItems.removeAll()
        freeItems.removeAll()
    }
}
extension ReuseController {
    mutating func dequeue<View: AnyObject>(at key: Key, rowBuilder: RowBuilder) -> Row where Row: ReuseItem<View> {
        guard let item = activeItems[key] else {
            let item = freeItems.popLast() ?? rowBuilder()
            activeItems[key] = item
            return item
        }
        item.free()
        return item
    }
    @discardableResult
    mutating func free<View: AnyObject>(at key: Key) -> Row? where Row: ReuseItem<View> {
        guard let item = activeItems[key] else { return nil }
        activeItems.removeValue(forKey: key)
        item.free()
        freeItems.append(item)
        return item
    }
}

#endif
