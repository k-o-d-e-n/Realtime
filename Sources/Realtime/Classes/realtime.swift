//
//  realtime.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/07/2018.
//

import Foundation

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

internal func debugPrintLog(_ message: String) {
    debugAction {
        debugPrint("Realtime log: \(message)")
    }
}

internal func debugFatalError(condition: @autoclosure () -> Bool = true,
                              _ message: @autoclosure () -> String = "", _ file: String = #file, _ line: Int = #line) {
    debugAction {
        if condition() {
            debugLog(message(), file, line)
            if ProcessInfo.processInfo.arguments.contains("REALTIME_CRASH_ON_ERROR") {
                fatalError(message())
            }
        }
    }
}

infix operator <==: AssignmentPrecedence

public struct RealtimeError: LocalizedError {
    let description: String
    public let source: Source

    public var localizedDescription: String { return description }

    init(source: Source, description: String) {
        self.source = source
        self.description = description
    }

    /// Shows part or process of Realtime where error is happened.
    ///
    /// - value: Error from someone class of property
    /// - collection: Error from someone class of collection
    /// - listening: Error from Listenable part
    /// - coding: Error on coding process
    /// - transaction: Error in `Transaction`
    /// - cache: Error in cache
    public enum Source {
        indirect case external(Error, Source)

        case value
        case file
        case collection

        case listening
        case coding
        case objectCoding([String: Error])
        case transaction([Error])
        case cache
        case database
        case storage
    }

    init(external error: Error, in source: Source, description: String = "") {
        self.source = .external(error, source)
        self.description = "External error: \(String(describing: error))"
    }
    init<T>(initialization type: T.Type, _ data: Any) {
        self.init(source: .coding, description: "Failed initialization type: \(T.self) with data: \(data)")
    }
    init<T>(decoding type: T.Type, _ data: Any, reason: String) {
        self.init(source: .coding, description: "Failed decoding data: \(data) to type: \(T.self). Reason: \(reason)")
    }
    init<T>(encoding value: T, reason: String) {
        self.init(source: .coding, description: "Failed encoding value of type: \(value). Reason: \(reason)")
    }
}
