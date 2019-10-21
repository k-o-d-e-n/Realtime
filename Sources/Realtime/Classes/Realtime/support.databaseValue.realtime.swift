
import Foundation

internal extension RealtimeDatabaseValue {
    init(bool value: Bool) {
        self.backend = .bool(value)
    }
    init(int8 value: Int8) {
        self.backend = .int8(value)
    }
    init(int16 value: Int16) {
        self.backend = .int16(value)
    }
    init(int32 value: Int32) {
        self.backend = .int32(value)
    }
    init(int64 value: Int64) {
        self.backend = .int64(value)
    }
    init(uint8 value: UInt8) {
        self.backend = .uint8(value)
    }
    init(uint16 value: UInt16) {
        self.backend = .uint16(value)
    }
    init(uint32 value: UInt32) {
        self.backend = .uint32(value)
    }
    init(uint64 value: UInt64) {
        self.backend = .uint64(value)
    }
    init(double value: Double) {
        self.backend = .double(value)
    }
    init(float value: Float) {
        self.backend = .float(value)
    }
    init(string value: String) {
        self.backend = .string(value)
    }
    init(data value: Data) {
        self.backend = .data(value)
    }
}

public protocol RealtimeDatabaseValueAdapter {
    associatedtype Value
    static func map(_ value: Value) -> RealtimeDatabaseValue
}
public protocol ExpressibleByRealtimeDatabaseValue {
    associatedtype RDBConvertor: RealtimeDatabaseValueAdapter where RDBConvertor.Value == Self
}
extension Bool: ExpressibleByRealtimeDatabaseValue {
    public enum RDBConvertor: RealtimeDatabaseValueAdapter {
        public static func map(_ value: Bool) -> RealtimeDatabaseValue { return RealtimeDatabaseValue(bool: value) }
    }
}
extension Int8: ExpressibleByRealtimeDatabaseValue {
    public enum RDBConvertor: RealtimeDatabaseValueAdapter {
        public static func map(_ value: Int8) -> RealtimeDatabaseValue { return RealtimeDatabaseValue(int8: value) }
    }
}
extension Int16: ExpressibleByRealtimeDatabaseValue {
    public enum RDBConvertor: RealtimeDatabaseValueAdapter {
        public static func map(_ value: Int16) -> RealtimeDatabaseValue { return RealtimeDatabaseValue(int16: value) }
    }
}
extension Int32: ExpressibleByRealtimeDatabaseValue {
    public enum RDBConvertor: RealtimeDatabaseValueAdapter {
        public static func map(_ value: Int32) -> RealtimeDatabaseValue { return RealtimeDatabaseValue(int32: value) }
    }
}
extension Int64: ExpressibleByRealtimeDatabaseValue {
    public enum RDBConvertor: RealtimeDatabaseValueAdapter {
        public static func map(_ value: Int64) -> RealtimeDatabaseValue { return RealtimeDatabaseValue(int64: value) }
    }
}
extension UInt8: ExpressibleByRealtimeDatabaseValue {
    public enum RDBConvertor: RealtimeDatabaseValueAdapter {
        public static func map(_ value: UInt8) -> RealtimeDatabaseValue { return RealtimeDatabaseValue(uint8: value) }
    }
}
extension UInt16: ExpressibleByRealtimeDatabaseValue {
    public enum RDBConvertor: RealtimeDatabaseValueAdapter {
        public static func map(_ value: UInt16) -> RealtimeDatabaseValue { return RealtimeDatabaseValue(uint16: value) }
    }
}
extension UInt32: ExpressibleByRealtimeDatabaseValue {
    public enum RDBConvertor: RealtimeDatabaseValueAdapter {
        public static func map(_ value: UInt32) -> RealtimeDatabaseValue { return RealtimeDatabaseValue(uint32: value) }
    }
}
extension UInt64: ExpressibleByRealtimeDatabaseValue {
    public enum RDBConvertor: RealtimeDatabaseValueAdapter {
        public static func map(_ value: UInt64) -> RealtimeDatabaseValue { return RealtimeDatabaseValue(uint64: value) }
    }
}
extension Double: ExpressibleByRealtimeDatabaseValue {
    public enum RDBConvertor: RealtimeDatabaseValueAdapter {
        public static func map(_ value: Double) -> RealtimeDatabaseValue { return RealtimeDatabaseValue(double: value) }
    }
}
extension Float: ExpressibleByRealtimeDatabaseValue {
    public enum RDBConvertor: RealtimeDatabaseValueAdapter {
        public static func map(_ value: Float) -> RealtimeDatabaseValue { return RealtimeDatabaseValue(float: value) }
    }
}
extension String: ExpressibleByRealtimeDatabaseValue {
    public enum RDBConvertor: RealtimeDatabaseValueAdapter {
        public static func map(_ value: String) -> RealtimeDatabaseValue { return RealtimeDatabaseValue(string: value) }
    }
}
extension Data: ExpressibleByRealtimeDatabaseValue {
    public enum RDBConvertor: RealtimeDatabaseValueAdapter {
        public static func map(_ value: Data) -> RealtimeDatabaseValue { return RealtimeDatabaseValue(data: value) }
    }
}


extension RealtimeDatabaseValue.Dictionary {
    public mutating func setValue(_ value: Bool, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Bool, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Bool, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Bool, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Bool, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Bool, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Bool, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Bool, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Bool, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Bool, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Bool, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Bool, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Bool, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: RealtimeDatabaseValue, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), value))
    }
    public mutating func setValue(_ value: Int8, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int8, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int8, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int8, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int8, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int8, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int8, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int8, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int8, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int8, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int8, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int8, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int8, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: RealtimeDatabaseValue, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), value))
    }
    public mutating func setValue(_ value: Int16, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int16, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int16, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int16, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int16, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int16, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int16, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int16, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int16, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int16, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int16, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int16, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int16, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: RealtimeDatabaseValue, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), value))
    }
    public mutating func setValue(_ value: Int32, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int32, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int32, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int32, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int32, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int32, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int32, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int32, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int32, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int32, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int32, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int32, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int32, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: RealtimeDatabaseValue, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), value))
    }
    public mutating func setValue(_ value: Int64, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int64, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int64, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int64, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int64, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int64, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int64, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int64, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int64, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int64, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int64, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int64, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Int64, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: RealtimeDatabaseValue, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), value))
    }
    public mutating func setValue(_ value: UInt8, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt8, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt8, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt8, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt8, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt8, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt8, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt8, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt8, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt8, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt8, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt8, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt8, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: RealtimeDatabaseValue, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), value))
    }
    public mutating func setValue(_ value: UInt16, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt16, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt16, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt16, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt16, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt16, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt16, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt16, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt16, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt16, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt16, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt16, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt16, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: RealtimeDatabaseValue, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), value))
    }
    public mutating func setValue(_ value: UInt32, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt32, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt32, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt32, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt32, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt32, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt32, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt32, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt32, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt32, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt32, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt32, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt32, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: RealtimeDatabaseValue, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), value))
    }
    public mutating func setValue(_ value: UInt64, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt64, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt64, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt64, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt64, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt64, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt64, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt64, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt64, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt64, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt64, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt64, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: UInt64, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: RealtimeDatabaseValue, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), value))
    }
    public mutating func setValue(_ value: Double, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Double, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Double, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Double, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Double, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Double, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Double, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Double, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Double, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Double, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Double, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Double, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Double, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: RealtimeDatabaseValue, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), value))
    }
    public mutating func setValue(_ value: Float, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Float, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Float, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Float, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Float, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Float, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Float, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Float, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Float, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Float, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Float, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Float, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Float, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: RealtimeDatabaseValue, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), value))
    }
    public mutating func setValue(_ value: String, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: String, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: String, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: String, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: String, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: String, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: String, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: String, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: String, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: String, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: String, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: String, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: String, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: RealtimeDatabaseValue, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), value))
    }
    public mutating func setValue(_ value: Data, forKey key: Bool) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Data, forKey key: Int8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Data, forKey key: Int16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Data, forKey key: Int32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Data, forKey key: Int64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Data, forKey key: UInt8) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Data, forKey key: UInt16) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Data, forKey key: UInt32) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Data, forKey key: UInt64) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Data, forKey key: Double) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Data, forKey key: Float) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Data, forKey key: String) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: Data, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
    }
    public mutating func setValue(_ value: RealtimeDatabaseValue, forKey key: Data) {
        properties.append((RealtimeDatabaseValue(key), value))
    }
}

public extension RealtimeDatabaseValue {
    func typed(as type: Bool.Type) throws -> Bool {
        guard case let .bool(v) = backend else { throw RealtimeError(source: .coding, description: "Mismatch type") }
        return v
    }
    func typed(as type: Int8.Type) throws -> Int8 {
        guard case let .int8(v) = backend else { throw RealtimeError(source: .coding, description: "Mismatch type") }
        return v
    }
    func typed(as type: Int16.Type) throws -> Int16 {
        guard case let .int16(v) = backend else { throw RealtimeError(source: .coding, description: "Mismatch type") }
        return v
    }
    func typed(as type: Int32.Type) throws -> Int32 {
        guard case let .int32(v) = backend else { throw RealtimeError(source: .coding, description: "Mismatch type") }
        return v
    }
    func typed(as type: Int64.Type) throws -> Int64 {
        guard case let .int64(v) = backend else { throw RealtimeError(source: .coding, description: "Mismatch type") }
        return v
    }
    func typed(as type: UInt8.Type) throws -> UInt8 {
        guard case let .uint8(v) = backend else { throw RealtimeError(source: .coding, description: "Mismatch type") }
        return v
    }
    func typed(as type: UInt16.Type) throws -> UInt16 {
        guard case let .uint16(v) = backend else { throw RealtimeError(source: .coding, description: "Mismatch type") }
        return v
    }
    func typed(as type: UInt32.Type) throws -> UInt32 {
        guard case let .uint32(v) = backend else { throw RealtimeError(source: .coding, description: "Mismatch type") }
        return v
    }
    func typed(as type: UInt64.Type) throws -> UInt64 {
        guard case let .uint64(v) = backend else { throw RealtimeError(source: .coding, description: "Mismatch type") }
        return v
    }
    func typed(as type: Double.Type) throws -> Double {
        guard case let .double(v) = backend else { throw RealtimeError(source: .coding, description: "Mismatch type") }
        return v
    }
    func typed(as type: Float.Type) throws -> Float {
        guard case let .float(v) = backend else { throw RealtimeError(source: .coding, description: "Mismatch type") }
        return v
    }
    func typed(as type: String.Type) throws -> String {
        guard case let .string(v) = backend else { throw RealtimeError(source: .coding, description: "Mismatch type") }
        return v
    }
    func typed(as type: Data.Type) throws -> Data {
        guard case let .data(v) = backend else { throw RealtimeError(source: .coding, description: "Mismatch type") }
        return v
    }
    func typed(as type: Int.Type) throws -> Int {
        switch backend {
        case .int8(let v): return Int(v)
        case .int16(let v): return Int(v)
        case .int32(let v): return Int(v)
        case .int64(let v): return Int(v)
        case .uint8(let v): return Int(v)
        case .uint16(let v): return Int(v)
        case .uint32(let v): return Int(v)
        case .uint64(let v): return Int(v)
        default: throw RealtimeError(source: .coding, description: "Mismatch type")
        }
    }
    func typed(as type: UInt.Type) throws -> UInt {
        switch backend {
        case .int8(let v): return UInt(v)
        case .int16(let v): return UInt(v)
        case .int32(let v): return UInt(v)
        case .int64(let v): return UInt(v)
        case .uint8(let v): return UInt(v)
        case .uint16(let v): return UInt(v)
        case .uint32(let v): return UInt(v)
        case .uint64(let v): return UInt(v)
        default: throw RealtimeError(source: .coding, description: "Mismatch type")
        }
    }
}

public extension RawRepresentable where Self.RawValue == String {
    func property(in obj: Object) -> Property<Bool> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Bool?> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Int8> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Int8?> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Int16> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Int16?> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Int32> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Int32?> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Int64> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Int64?> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<UInt8> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<UInt8?> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<UInt16> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<UInt16?> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<UInt32> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<UInt32?> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<UInt64> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<UInt64?> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Double> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Double?> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Float> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Float?> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<String> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<String?> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Data> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property(in obj: Object) -> Property<Data?> {
        return property(in: obj, representer: .realtimeDataValue)
    }
//    func property(in obj: Object) -> Property<Int> {
//        return property(in: obj, representer: .realtimeDataValue)
//    }
//    func property(in obj: Object) -> Property<Int?> {
//        return property(in: obj, representer: .realtimeDataValue)
//    }
//    func property(in obj: Object) -> Property<UInt> {
//        return property(in: obj, representer: .realtimeDataValue)
//    }
//    func property(in obj: Object) -> Property<UInt?> {
//        return property(in: obj, representer: .realtimeDataValue)
//    }
}
