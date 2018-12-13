//
//  other.swift
//  Realtime_Tests
//
//  Created by Denis Koryttsev on 11/08/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import XCTest
@testable import Realtime

// UIKit support

class OtherTests: XCTestCase {
    func testControlListening() {
        var counter = 0
        let control = UIControl()

        let disposable = control.onEvent(.touchUpInside).listening({ _ in
            counter += 1
        })

        control.sendActions(for: .touchUpInside)

        XCTAssertTrue(counter == 1)

        control.sendActions(for: .touchUpInside)
        control.sendActions(for: .touchDown)

        XCTAssertTrue(counter == 2)

        disposable.dispose()

        control.sendActions(for: .touchUpInside)

        XCTAssertTrue(counter == 2)
    }
}

// MARK: Other

extension OtherTests {
    func testAnyOf() {
        XCTAssertTrue(2 ∈ [1,2,3]) // true
        XCTAssertTrue("Two" ∈ ["One", "Two", "Three"])

        XCTAssertTrue(any(of: 1,2,3)(2)) // true
        XCTAssertTrue(any(of: "One", "Two", "Three")("Two"))
    }
    func testAnyCollection() {
        var calculator: Int = 0
        let mapValue: (Int) -> Int = { _ in calculator += 1; return calculator }
        var source = [0]
        let one = SharedCollection(source)

        let lazyOne = one.lazy.map(mapValue)
        _ = lazyOne.first
        XCTAssertTrue(calculator == 1)
        let anyLazyOne = AnySharedCollection(lazyOne)
        XCTAssertTrue(calculator == 1)
        source.append(1)
        XCTAssertTrue(one.count == 2)
        XCTAssertTrue(lazyOne.count == 2)
        XCTAssertTrue(anyLazyOne.count == 2)
    }
    func testMirror() {
        let object = Object(in: .root)
        let mirror = Mirror(reflecting: object)

        XCTAssert(mirror.children.count > 0)
        mirror.children.forEach { (child) in
            print(child.label as Any, child.value)
        }

        mirror.children.forEach { (child) in
            print(child.label as Any, child.value)
        }

        let id = ObjectIdentifier.init(object)
        print(id)
    }
    func testReflectEnum() {
        enum Test {
            case one(Any), two(Any)
        }
        let one = Test.one(false)
        let oneMirror = Mirror(reflecting: one)
        let testMirror = Mirror(reflecting: Test.self)

        print(oneMirror, testMirror)
    }

    func testCodableEnum() {
        struct Err: Error {
            var localizedDescription: String { return "" }
        }
        struct News: Codable {
            let date: TimeInterval
        }
        enum Feed: Codable {
            case common(News)

            enum Key: CodingKey {
                case raw
            }

            init(from decoder: Decoder) throws {
                let rawContainer = try decoder.container(keyedBy: Key.self)
                let container = try decoder.singleValueContainer()
                let rawValue = try rawContainer.decode(Int.self, forKey: .raw)
                switch rawValue {
                case 0:
                    self = .common(try container.decode(News.self))
                default:
                    throw Err()
                }
            }

            func encode(to encoder: Encoder) throws {
                switch self {
                case .common(let news):
                    var container = encoder.singleValueContainer()
                    try container.encode(news)
                    var rawContainer = encoder.container(keyedBy: Key.self)
                    try rawContainer.encode(0, forKey: .raw)
                }
            }
        }

        do {
            let news = News(date: 0.0)
            let feed: Feed = .common(news)

            let data = try JSONEncoder().encode(feed)

            let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as! NSDictionary
            let decodedFeed = try JSONDecoder().decode(Feed.self, from: data)

            XCTAssertTrue(["raw": 0, "date": 0.0] as NSDictionary == json)
            switch decodedFeed {
            case .common(let n):
                XCTAssertTrue(n.date == news.date)
            }
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testEnumStringInterpolation() {
        XCTAssertNotEqual("__raw/__mv", "\(InternalKeys.raw)/\(InternalKeys.modelVersion)")
    }

//    func testNodeLimitExceeded() {
//        let node = Node.root.child(with: (0..<32).lazy.map(String.init).joined(separator: "/"))
//        XCTFail("\(node.underestimatedCount) levels")
//    }
}

final class SharedCollection<Base: MutableCollection>: MutableCollection {
    func index(after i: Base.Index) -> Base.Index {
        return base.index(after: i)
    }

    subscript(position: Base.Index) -> Base.Iterator.Element {
        get {
            return base[position]
        }
        set(newValue) {
            base[position] = newValue
        }
    }

    var endIndex: Base.Index { return base.endIndex }
    var startIndex: Base.Index { return base.startIndex }

    typealias Index = Base.Index

    /// Returns an iterator over the elements of this sequence.
    func makeIterator() -> Base.Iterator {
        return base.makeIterator()
    }

    var base: Base

    init(_ base: Base) {
        self.base = base
    }
}
extension SharedCollection where Base == Array<Int> {
    func append(_ elem: Int) {
        base.append(elem)
    }
}

infix operator ∈
func ∈ <T: Equatable>(lhs: T, rhs: [T]) -> Bool {
    return rhs.contains(lhs)
}

func any<T: Equatable>(of values: T...) -> (T) -> Bool {
    return { values.contains($0) }
}

internal func _makeCollectionDescription<C: Collection>(_ collection: C,
    withTypeName type: String? = nil
    ) -> String {
    var result = ""
    if let type = type {
        result += "\(type)(["
    } else {
        result += "["
    }

    var first = true
    for item in collection {
        if first {
            first = false
        } else {
            result += ", "
        }
        debugPrint(item, terminator: "", to: &result)
    }
    result += type != nil ? "])" : "]"
    return result
}
