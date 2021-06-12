//
//  form.support.realtime.swift
//  Realtime
//
//  Created by Denis Koryttsev on 11/09/2018.
//

#if os(iOS)
import UIKit

extension UITableView {
    public enum Operation {
        case reload
        case move(IndexPath)
        case insert
        case delete
        case none

        var isActive: Bool {
            if case .none = self {
                return false
            }
            return true
        }
    }

    func scheduleOperation(_ operation: Operation, for indexPath: IndexPath, with animation: UITableView.RowAnimation) {
        switch operation {
        case .none: break
        case .reload: reloadRows(at: [indexPath], with: animation)
        case .move(let ip): moveRow(at: indexPath, to: ip)
        case .insert: insertRows(at: [indexPath], with: animation)
        case .delete: deleteRows(at: [indexPath], with: animation)
        }
    }

    public class ScheduledUpdate {
        internal private(set) var events: [IndexPath: UITableView.Operation]
        var operations: [(IndexPath, UITableView.Operation)] = []
        var isReadyToUpdate: Bool { return events.isEmpty && !operations.isEmpty }

        public init(events: [IndexPath: UITableView.Operation]) {
            precondition(!events.isEmpty, "Events must not be empty")
            self.events = events
        }

        func fulfill(_ indexPath: IndexPath) -> Bool {
            if let operation = events.removeValue(forKey: indexPath) {
                operations.append((indexPath, operation))
                return true
            } else {
                return false
            }
        }

        func batchUpdatesIfFulfilled(in tableView: UITableView) {
            while !operations.isEmpty {
                let (ip, op) = operations.removeLast()
                tableView.scheduleOperation(op, for: ip, with: .automatic)
            }
        }
    }
}

/*extension AnyRealtimeCollection: DynamicSectionDataSource {}
extension Values: DynamicSectionDataSource {}
extension AssociatedValues: DynamicSectionDataSource {}
extension References: DynamicSectionDataSource {}
extension MapRealtimeCollection: DynamicSectionDataSource {}
extension FlattenRealtimeCollection: DynamicSectionDataSource {}*/

public struct RealtimeCollectionDataSource<Model>: DynamicSectionDataSource {
    let base: AnyRealtimeCollection<Model>
    public init(_ base: AnyRealtimeCollection<Model>) { self.base = base }
    public init<RC>(_ collection: RC) where RC: RealtimeCollection, RC.Element == Model, RC.View.Element: DatabaseKeyRepresentable {
        self.base = AnyRealtimeCollection(collection)
    }
    public var changes: AnyListenable<DynamicSectionEvent> { base.changes }
    public var keepSynced: Bool {
        get { base.keepSynced }
        set { base.keepSynced = newValue }
    }
    public var count: Int { base.count }
    public subscript(index: Int) -> Model { base[base.index(base.startIndex, offsetBy: index)] }
}
#endif
