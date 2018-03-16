//
//  RealtimeLinks.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

/// Link value describing reference to some location of database.

private enum LinkNodes {
    static let path = "pth"
    static let sourceID = "s_id"
}

struct Reference: DataSnapshotRepresented {
    let ref: String

    init(ref: String) {
        self.ref = ref
    }

    var localValue: Any? { return ref }
    init?(snapshot: DataSnapshot) {
        guard let ref: String = snapshot.flatMap() ?? LinkNodes.path.map(from: snapshot) else { return nil } // TODO: Remove ?? ..., after move to new version data model
        self.ref = ref
    }
}
extension Reference {
    func make<V: RealtimeValue>(in node: Node = .root) -> V { return V(in: node.child(with: ref)) }
}
extension RealtimeValue {
    func makeReference(from node: Node = .root) -> Reference! { return Reference(ref: self.node!.path(from: node)) }
    func makeRelation(from node: Node = .root, use sourceID: String? = nil) -> Relation! {
        return Relation(sourceID: sourceID ?? DatabaseReference.root().childByAutoId().key, ref: makeReference(from: node))
    }
}

struct Relation: DataSnapshotRepresented {
    let sourceID: String
    let ref: Reference

    init(sourceID: String, ref: Reference) {
        self.sourceID = sourceID
        self.ref = ref
    }

    var localValue: Any? { return [LinkNodes.path: ref.ref, LinkNodes.sourceID: sourceID] }
    init?(snapshot: DataSnapshot) {
        guard
            let sourceID: String = LinkNodes.sourceID.map(from: snapshot),
            let ref = Reference(snapshot: snapshot)
            else {
                // TODO: Remove after move to new version data model
                guard let ref = Reference(snapshot: snapshot) else { return nil }
                self.ref = ref
                self.sourceID = snapshot.key
                return
        }

        self.sourceID = sourceID
        self.ref = ref
    }
}

public struct SourceLink: DataSnapshotRepresented {
    let links: [String]
    let id: String

    init(id: String, links: [String]) {
        self.id = id
        self.links = links
    }

    public var localValue: Any? { return links }
    public init?(snapshot: DataSnapshot) {
        guard let links: [String] = snapshot.flatMap() else { return nil }
        self.id = snapshot.key
        self.links = links
    }
}
