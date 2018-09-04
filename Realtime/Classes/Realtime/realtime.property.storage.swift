//
//  realtime.property.storage.swift
//  Realtime
//
//  Created by Denis Koryttsev on 30/07/2018.
//

import Foundation
import FirebaseStorage

public extension RawRepresentable where Self.RawValue == String {
    func readonlyFile<T>(from node: Node?, representer: Representer<T>) -> ReadonlyFile<T> {
        return ReadonlyFile(in: Node(key: rawValue, parent: node), representer: representer)
    }
    func readonlyFile<T>(from node: Node?, representer: Representer<T>) -> ReadonlyFile<T?> {
        return ReadonlyFile(in: Node(key: rawValue, parent: node), representer: representer)
    }
    func file<T>(from node: Node?, representer: Representer<T>) -> File<T> {
        return File(in: Node(key: rawValue, parent: node), representer: representer)
    }
    func file<T>(from node: Node?, representer: Representer<T>) -> File<T?> {
        return File(in: Node(key: rawValue, parent: node), representer: representer)
    }
}

/// Defines readonly property for files storage
public final class ReadonlyFile<T>: ReadonlyProperty<T> {
    override var updateType: ValueNode.Type { return FileNode.self }

    public override func load(completion: Assign<Error?>?) {
        guard let node = self.node, node.isRooted else {
            fatalError("Can`t get database reference in \(self). Object must be rooted.")
        }

        node.file().getData(maxSize: .max) { (data, err) in
            if let e = err {
                self._setError(e)
                completion?.assign(e)
            } else {
                do {
                    if let value = try self.representer.decode(FileNode(node: node, value: data)) {
                        self._setValue(.remote(value))
                    } else {
                        self._setRemoved()
                    }
                    completion?.assign(nil)
                } catch let e {
                    self._setError(e)
                    completion?.assign(e)
                }
            }
        }
    }
}

/// Defines read/write property for files storage
public final class File<T>: Property<T> {
    override var updateType: ValueNode.Type { return FileNode.self }

    public override func load(completion: Assign<Error?>?) {
        guard let node = self.node, node.isRooted else {
            fatalError("Can`t get database reference in \(self). Object must be rooted.")
        }

        node.file().getData(maxSize: .max) { (data, err) in
            if let e = err {
                self._setError(e)
                completion?.assign(e)
            } else {
                do {
                    if let value = try self.representer.decode(FileNode(node: node, value: data)) {
                        self._setValue(.remote(value))
                    } else {
                        self._setRemoved()
                    }
                    completion?.assign(nil)
                } catch let e {
                    self._setError(e)
                    completion?.assign(e)
                }
            }
        }
    }
}
