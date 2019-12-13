#if !canImport(ObjectiveC)
import XCTest

extension ListenableTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ListenableTests = [
        ("testAccumulator", testAccumulator),
        ("testAccumulator2", testAccumulator2),
        ("testAsyncReadonlyValue", testAsyncReadonlyValue),
        ("testAvoidSimultaneousAccessInP", testAvoidSimultaneousAccessInP),
        ("testBindProperty", testBindProperty),
        ("testClosure", testClosure),
        ("testCombine", testCombine),
        ("testConcurrency", testConcurrency),
        ("testDeadline", testDeadline),
        ("testDebounce", testDebounce),
        ("testDistinctUntilChangedPropertyClass", testDistinctUntilChangedPropertyClass),
        ("testDoubleFilterPropertyClass", testDoubleFilterPropertyClass),
        ("testDoubleMapPropertyClass", testDoubleMapPropertyClass),
        ("testDoubleOnReceiveMapPropertyClass", testDoubleOnReceiveMapPropertyClass),
        ("testDoubleOnReceivePropertyClass", testDoubleOnReceivePropertyClass),
        ("testFilterPropertyClass", testFilterPropertyClass),
        ("testListeningDisposable", testListeningDisposable),
        ("testListeningItem", testListeningItem),
        ("testListeningStore", testListeningStore),
        ("testLivetime", testLivetime),
        ("testMapPropertyClass", testMapPropertyClass),
        ("testMemoizeOneSendLast", testMemoizeOneSendLast),
        ("testOldValueBasedOnMemoize", testOldValueBasedOnMemoize),
        ("testOnce", testOnce),
        ("testOnce2", testOnce2),
        ("testOnFire", testOnFire),
        ("testOnReceiveMapPropertyClass", testOnReceiveMapPropertyClass),
        ("testOnReceivePropertyClass", testOnReceivePropertyClass),
        ("testPreprocessorAsListenable", testPreprocessorAsListenable),
        ("testProperty", testProperty),
        ("testReadonlyValue", testReadonlyValue),
        ("testRepeater", testRepeater),
        ("testRepeaterListeiningItem", testRepeaterListeiningItem),
        ("testRepeaterLocked", testRepeaterLocked),
        ("testRepeaterOnQueue", testRepeaterOnQueue),
        ("testRepeaterOnRunloop", testRepeaterOnRunloop),
        ("testRepeaterSubscriber", testRepeaterSubscriber),
        ("testShareContinuous", testShareContinuous),
        ("testSharedContinuous", testSharedContinuous),
        ("testSharedRepeatable", testSharedRepeatable),
        ("testShareRepeatable", testShareRepeatable),
        ("testStrongProperty", testStrongProperty),
        ("testSuspend", testSuspend),
        ("testTrivial", testTrivial),
        ("testWeakProperty", testWeakProperty),
        ("testWeakProperty2", testWeakProperty2),
    ]
}

extension RealtimeTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__RealtimeTests = [
        ("testAssociatedValuesWithVersionAndRawValues", testAssociatedValuesWithVersionAndRawValues),
        ("testCacheFileDownloadTask", testCacheFileDownloadTask),
        ("testCacheObject", testCacheObject),
        ("testCollectionOnRootObject", testCollectionOnRootObject),
        ("testCollectionOnStandaloneObject", testCollectionOnStandaloneObject),
        ("testConnectNode", testConnectNode),
        ("testDatabaseBinding", testDatabaseBinding),
        ("testDecoding", testDecoding),
        ("testDisconnectNode", testDisconnectNode),
        ("testEqualFailsOptionalPropertyWithoutValueAndValue", testEqualFailsOptionalPropertyWithoutValueAndValue),
        ("testEqualFailsOptionalPropertyWithValueAndValue", testEqualFailsOptionalPropertyWithValueAndValue),
        ("testEqualFailsRequiredPropertyWithoutValueAndValue", testEqualFailsRequiredPropertyWithoutValueAndValue),
        ("testEqualFailsRequiredPropertyWithValueAndValue", testEqualFailsRequiredPropertyWithValueAndValue),
        ("testEqualOptionalPropertyWithNilValueAndNil", testEqualOptionalPropertyWithNilValueAndNil),
        ("testEqualRequiredPropertyWithoutValueAndNil", testEqualRequiredPropertyWithoutValueAndNil),
        ("testGetAncestorOnLevelUp", testGetAncestorOnLevelUp),
        ("testInitializeWithPayload", testInitializeWithPayload),
        ("testInitializeWithPayload3", testInitializeWithPayload3),
        ("testInitializeWithPayload4", testInitializeWithPayload4),
        ("testLinksNode", testLinksNode),
        ("testListeningCollectionChangesOnInsert", testListeningCollectionChangesOnInsert),
        ("testLoadFileState", testLoadFileState),
        ("testLoadTask", testLoadTask),
        ("testLoadValue", testLoadValue),
        ("testLocalChangesArray", testLocalChangesArray),
        ("testLocalChangesDictionary", testLocalChangesDictionary),
        ("testLocalChangesLinkedArray", testLocalChangesLinkedArray),
        ("testLocalDatabase", testLocalDatabase),
        ("testMergeTransactions", testMergeTransactions),
        ("testNestedObjectChanges", testNestedObjectChanges),
        ("testNode", testNode),
        ("testNotEqualOptionalPropertyWithoutValueAndValue", testNotEqualOptionalPropertyWithoutValueAndValue),
        ("testNotEqualOptionalPropertyWithValueAndNil", testNotEqualOptionalPropertyWithValueAndNil),
        ("testNotEqualOptionalPropertyWithValueAndValue", testNotEqualOptionalPropertyWithValueAndValue),
        ("testNotEqualRequiredPropertyWithoutValueAndValue", testNotEqualRequiredPropertyWithoutValueAndValue),
        ("testNotEqualRequiredPropertyWithValueAndNil", testNotEqualRequiredPropertyWithValueAndNil),
        ("testNotEqualRequiredPropertyWithValueAndValue", testNotEqualRequiredPropertyWithValueAndValue),
        ("testObjectRemove", testObjectRemove),
        ("testObjectSave", testObjectSave),
        ("testObjectVersionerEmpty", testObjectVersionerEmpty),
        ("testObserveCache", testObserveCache),
        ("testOptionalReference", testOptionalReference),
        ("testOptionalRelation", testOptionalRelation),
        ("testPayload", testPayload),
        ("testPropertySetValue", testPropertySetValue),
        ("testReadonlyReference", testReadonlyReference),
        ("testReadonlyRelation", testReadonlyRelation),
        ("testRealtimeDatabaseValue", testRealtimeDatabaseValue),
        ("testRealtimeDatabaseValueExtractBool", testRealtimeDatabaseValueExtractBool),
        ("testRealtimeDatabaseValueExtractData", testRealtimeDatabaseValueExtractData),
        ("testReferenceFireValue", testReferenceFireValue),
        ("testReferenceRepresentationPayload", testReferenceRepresentationPayload),
        ("testReflector", testReflector),
        ("testRelationManyToOne", testRelationManyToOne),
        ("testRelationOneToMany", testRelationOneToMany),
        ("testRelationOneToOne", testRelationOneToOne),
        ("testRelationPayload", testRelationPayload),
        ("testRemoveFile", testRemoveFile),
        ("testRemovePropertyValue", testRemovePropertyValue),
        ("testRepresenterOptional", testRepresenterOptional),
        ("testTimoutOnLoad", testTimoutOnLoad),
        ("testUpdateFileAfterSave", testUpdateFileAfterSave),
        ("testVersionableObject", testVersionableObject),
        ("testVersionableValue", testVersionableValue),
        ("testVersionableValue2", testVersionableValue2),
        ("testVersionableValue3", testVersionableValue3),
        ("testVersioner", testVersioner),
        ("testVersioner2", testVersioner2),
        ("testWriteRequiredPropertyFailsOnSave", testWriteRequiredPropertyFailsOnSave),
        ("testWriteRequiredPropertySuccessOnDecode", testWriteRequiredPropertySuccessOnDecode),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(ListenableTests.__allTests__ListenableTests),
        testCase(RealtimeTests.__allTests__RealtimeTests),
    ]
}
#endif
