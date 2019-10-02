//
//  AllTests.swift
//  RealtimeTests
//
//  Created by Denis Koryttsev on 02/10/2019.
//

import XCTest
import RealtimeTestLib
import Realtime

final class RunTests: NSObject {
    override init() {
        super.init()
        let configuration = RealtimeApp.Configuration(linksNode: BranchNode(key: "___tests/__links"))
        RealtimeApp.initialize(with: RealtimeApp.cache, storage: RealtimeApp.cache, configuration: configuration)
    }
}
