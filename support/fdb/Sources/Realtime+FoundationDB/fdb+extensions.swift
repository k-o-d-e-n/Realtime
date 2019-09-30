//
//  fdb+extensions.swift
//  fdb_client
//
//  Created by Denis Koryttsev on 17/06/2019.
//

import Foundation
@testable import FoundationDB

extension Tuple {
    struct RangeEnd: TupleConvertible {
        struct FoundationDBTupleAdapter: TupleAdapter {
            static let typeCodes: Set<UInt8> = [EntryType.rangeEnd.rawValue]
            static func read(from buffer: Data, at offset: Int) throws -> RangeEnd {
                guard buffer[offset] == 0xFF else { throw TupleDecodingError.incorrectTypeCode(index: offset, desired: [EntryType.rangeEnd.rawValue], actual: buffer[offset]) }
                return RangeEnd()
            }
            static func write(value: Tuple.RangeEnd, into buffer: inout Data) {
                buffer.append(0xFF)
            }
        }
    }
    func readAny(at index: Index) throws -> Any {
        guard let type = type(at: index) else { throw TupleDecodingError.missingField(index: index) }

        switch type {
        case .null: return try read(at: index) as NSNull
        case .falseValue, .trueValue: return try read(at: index) as Bool
        case .double: return try read(at: index) as Double
        case .float: return try read(at: index) as Float
        case .integer: return try read(at: index) as Int // todo: UInt64 not available
        case .string: return try read(at: index) as String
        case .byteArray: return try read(at: index) as Data
        case .tuple: return try read(at: index) as Tuple
        case .uuid: return try read(at: index) as UUID
        case .rangeEnd: return RangeEnd()
        }
    }

    func readStringPath() throws -> String {
        var path = ""
        try (0..<count).forEach { (i) in
            path += try read(at: i) as String
        }

        return path
    }

    init<S: Sequence>(elements: S) where S.Element: TupleConvertible {
        self.init()
        elements.forEach({ self.append($0) })
    }

    func prefix(upTo index: Index) -> Tuple {
        precondition(index <= count, "Index out of range")
        return Tuple(data: index == count ? data : data.prefix(upTo: offsets[index]), offsets: Array(offsets.prefix(upTo: index)))
    }
}

extension DatabaseValue {
    /**
     Add the contents of another database value to the end of this one.

     - parameter value:        The value to append to the end of this value.
     */
    public mutating func append(_ value: DatabaseValue) {
        data.append(value.data)
    }

    /**
     Add a byte to the end of this value.

     - parameter byte:        The byte to append to the end of this value.
     */
    public mutating func append(byte: UInt8) {
        data.append(byte)
    }

    /**
     Create a new database value which contains the contents of this
     database value concatenated with the provided database value.

     - parameter suffix:        The suffix to add to the end of the returned value.
     - returns:                A concatentation of this value and the provided suffix.
     */
    public func withSuffix(_ suffix: DatabaseValue) -> DatabaseValue {
        var newData = Data(capacity: data.count + suffix.data.count)
        newData.append(data)
        newData.append(suffix.data)
        return DatabaseValue(newData)
    }

    /**
     Create a new database value which contains the contents of this
     database value but with the given byte appended to the end.

     - parameter suffix:        The suffix byte to add to the end of the returned value.
     - returns:                A concatentation of this value and the provided suffix.
     */
    public func withSuffix(byte: UInt8) -> DatabaseValue {
        var newData = Data(capacity: data.count + 1)
        newData.append(data)
        newData.append(byte)
        return DatabaseValue(newData)
    }
}
extension ResultSet {
    public func read(_ key: DatabaseValue) -> DatabaseValue? {
        return read(key, range: rows.startIndex..<rows.endIndex)
    }

    public func read(_ key: DatabaseValue, range: Range<Int>) -> DatabaseValue? {
        let middleIndex = range.lowerBound + (range.upperBound - range.lowerBound) / 2
        guard range.contains(middleIndex) else {
            return nil
        }
        let middleKey = rows[middleIndex].key
        if middleKey == key {
            return rows[middleIndex].value
        }
        else if middleIndex == range.lowerBound {
            return nil
        }
        else if middleKey < key {
            return read(key, range: middleIndex ..< range.upperBound)
        }
        else {
            return read(key, range: range.lowerBound ..< middleIndex)
        }
    }

    public typealias Row = (key: DatabaseValue, value: DatabaseValue)
    public enum Child {
        case single(DatabaseValue?)
        case multiple(children: ResultSet, deepRows: [DatabaseValue: [Row]])
    }
}

extension UInt: TupleConvertible {
    public struct FoundationDBTupleAdapter: TupleAdapter {
        public typealias ValueType = UInt
        public static let typeCodes = integerTypeCodes()
    }
}

extension Collection {
    func splitPrefix(while predicate: (Element) throws -> Bool) rethrows -> (prefix: Self.SubSequence, suffix: Self.SubSequence) {
        var isPrefix = true
        var iterator = makeIterator()
        var index: Index = startIndex
        while let next = iterator.next(), isPrefix {
            if try predicate(next) {
                index = self.index(after: index)
            } else {
                isPrefix = false
            }
        }
        return (prefix(upTo: index), suffix(from: index))
    }

    func filterPrefix(where predicate: (Element) throws -> ComparisonResult) rethrows -> (prefix: (unsatisfied: Self.SubSequence, satisfied: Self.SubSequence), suffix: Self.SubSequence) {
        var result = ComparisonResult.orderedAscending
        var iterator = makeIterator()
        var ascendingIndex = startIndex
        var sameIndex: Index = startIndex
        while let next = iterator.next(), result != .orderedDescending {
            result = try predicate(next)
            switch result {
            case .orderedAscending:
                ascendingIndex = self.index(after: ascendingIndex)
                sameIndex = ascendingIndex
            case .orderedSame:
                sameIndex = self.index(after: sameIndex)
            case .orderedDescending: break
            }
        }
        return ((prefix(upTo: ascendingIndex), self[ascendingIndex..<sameIndex]), suffix(from: sameIndex))
    }
}

extension Collection where Element == ResultSet.Row {
    func child(for key: Tuple) -> ResultSet.Child {
        let rows = filterPrefix(where: { kv in
            let rowKey = Tuple(databaseValue: kv.key)
            switch rowKey.count {
            case ..<key.count: return .orderedAscending
            case key.count: return .orderedSame
            default: return .orderedDescending
            }
        })
        guard let equal = rows.prefix.satisfied.first(where: { $0.key == key.databaseValue }) else {
            let deepRows = rows.suffix.reduce(into: [DatabaseValue: [(DatabaseValue, DatabaseValue)]]()) { (res, keyValue) in
                let keyTuple = Tuple(databaseValue: keyValue.key)
                guard keyTuple.count > key.count else { return }
                let child = keyTuple.prefix(upTo: key.count + 1)
                if res[child.databaseValue] == nil {
                    res[child.databaseValue] = [keyValue]
                } else {
                    res[child.databaseValue]?.append(keyValue)
                }
            }
            return .multiple(children: ResultSet(rows: Array(rows.prefix.satisfied)), deepRows: deepRows)
        }

        return .single(equal.value)
    }

    func child(_ key: DatabaseValue) -> ResultSet.Child {
        guard isEmpty else {
            return _unsafeChild(key, range: startIndex ..< endIndex)
        }

        return .single(nil)
    }

    internal func _unsafeChild(_ key: DatabaseValue, range: Range<Index>) -> ResultSet.Child {
        let middleIndex = index(range.lowerBound, offsetBy: distance(from: range.lowerBound, to: range.upperBound) / 2)
        let middleKey = self[middleIndex].key
        guard middleKey == key else {
            if middleIndex == range.lowerBound {
                let key = Tuple(databaseValue: key)
                let nextRows = self[middleIndex ..< endIndex]
                let rows = nextRows.splitPrefix(while: { Tuple(databaseValue: $0.key).count == key.count + 1 })
                let deepRows = rows.suffix.reduce(into: [DatabaseValue: [(DatabaseValue, DatabaseValue)]]()) { (res, keyValue) in
                    let keyTuple = Tuple(databaseValue: keyValue.key)
                    guard keyTuple.count > key.count else { return }
                    let child = keyTuple.prefix(upTo: key.count + 1)
                    if res[child.databaseValue] == nil {
                        res[child.databaseValue] = [keyValue]
                    } else {
                        res[child.databaseValue]?.append(keyValue)
                    }
                }
                return .multiple(children: ResultSet(rows: Array(rows.prefix)), deepRows: deepRows)
            }
            else if middleKey < key {
                return _unsafeChild(key, range: middleIndex ..< range.upperBound)
            }
            else {
                return _unsafeChild(key, range: range.lowerBound ..< middleIndex)
            }
        }

        return .single(self[middleIndex].value)
    }
}
