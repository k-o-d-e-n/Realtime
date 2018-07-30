//
//  realtime.property.storage.swift
//  Realtime
//
//  Created by Denis Koryttsev on 30/07/2018.
//

import Foundation
import FirebaseStorage

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
