//
//  realtime.property.storage.swift
//  Realtime
//
//  Created by Denis Koryttsev on 30/07/2018.
//

import Foundation
import FirebaseStorage

public extension RawRepresentable where Self.RawValue == String {
    func readonlyFile<T>(from node: Node?, representer: Representer<T>) -> ReadonlyStorageProperty<T> {
        return ReadonlyStorageProperty(in: Node(key: rawValue, parent: node), options: [.representer: representer])
    }
    func readonlyFile<T>(from node: Node?, representer: Representer<T> = .any) -> ReadonlyStorageProperty<T?> {
        return readonlyFile(from: node, representer: representer.optional())
    }
    func file<T>(from node: Node?, representer: Representer<T>) -> StorageProperty<T> {
        return StorageProperty(in: Node(key: rawValue, parent: node), options: [.representer: representer])
    }
    func file<T>(from node: Node?, representer: Representer<T>) -> StorageProperty<T?> {
        return file(from: node, representer: representer.optional())
    }
}

public class ReadonlyStorageProperty<T>: ReadonlyRealtimeProperty<T> {
    override var updateType: ValueNode.Type { return FileNode.self }

    public override func load(completion: Assign<Error?>?) {
        guard let node = self.node, node.isRooted else {
            debugFatalError(condition: true, "Couldn`t get reference")
            completion?.assign(RealtimeError("Couldn`t get reference"))
            return
        }

        node.file().getData(maxSize: .max) { (data, err) in
            if let e = err {
                self.setError(e)
                completion?.assign(e)
            } else {
                do {
                    self._setListenValue(.remote(try self.representer.decode(FileNode(node: node, value: data)), strong: true))
                    completion?.assign(nil)
                } catch let e {
                    self.setError(e)
                    completion?.assign(e)
                }
            }
        }
    }
}

public class StorageProperty<T>: RealtimeProperty<T> {
    override var updateType: ValueNode.Type { return FileNode.self }

    public override func load(completion: Assign<Error?>?) {
        guard let node = self.node, node.isRooted else {
            debugFatalError(condition: true, "Couldn`t get reference")
            completion?.assign(RealtimeError("Couldn`t get reference"))
            return
        }

        node.file().getData(maxSize: .max) { (data, err) in
            if let e = err {
                self.setError(e)
                completion?.assign(e)
            } else {
                do {
                    self._setListenValue(.remote(try self.representer.decode(FileNode(node: node, value: data)), strong: true))
                    completion?.assign(nil)
                } catch let e {
                    self.setError(e)
                    completion?.assign(e)
                }
            }
        }
    }
}
