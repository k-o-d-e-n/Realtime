# Realtime

[![CI Status](http://img.shields.io/travis/k-o-d-e-n/Realtime.svg?style=flat)](https://travis-ci.org/k-o-d-e-n/Realtime)
[![Version](https://img.shields.io/cocoapods/v/Realtime.svg?style=flat)](http://cocoapods.org/pods/Realtime)
[![License](https://img.shields.io/cocoapods/l/Realtime.svg?style=flat)](http://cocoapods.org/pods/Realtime)
[![Platform](https://img.shields.io/cocoapods/p/Realtime.svg?style=flat)](http://cocoapods.org/pods/Realtime)

Realtime is database framework based on Firebase that makes the creation of complex database structures is simple.
Realtime can help you to create app quicker than if use clear Firebase API herewith to apply complex structures to store data in Firebase database, to update UI using reactive behaviors.
Realtime provides lightweight data traffic, lazy initialization of data, good distribution of data.

## Features

:point_right:  **Simple scalable model structure**

:point_right: **Files**

:point_right:  **Collections**

:point_right:  **References**

:point_right:  **UI support**

## Usage

### Model

To create any model data structure you can make by subclassing `RealtimeObject`.
You can define child properties using classes:
+ `RealtimeObject` subclasses;
+ `RealtimeProperty` (typealias `RealtimeProperty`);
+ `LinkedRealtimeArray`, `RealtimeArray`, `RealtimeDictionary`;
If you use lazy properties, you need implement class function `lazyPropertyKeyPath(for:)`. (Please tell me if you know how avoid it, without inheriting NSObject).
This function called for each subclass, therefore you don't need call super implementation. 
Example:
```swift
class User: RealtimeObject {
    lazy var name: RealtimeProperty<String> = "name".property(from: self.node)
    lazy var age: RealtimeProperty<Int> = "age".property(from: self.node)
    lazy var photo: StorageProperty<UIImage?> = StorageProperty(in: Node(key: "photo", parent: self.node), representer: Representer.png.optional())
    lazy var groups: LinkedRealtimeArray<RealtimeGroup> = "groups".linkedArray(from: self.node, elements: Global.rtGroups.node!)
    lazy var scheduledConversations: RealtimeArray<Conversation> = "scheduledConversations".array(from: self.node)
    lazy var ownedGroup: RealtimeRelation<RealtimeGroup?> = "ownedGroup".relation(from: self.node, "manager")

    override class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "name": return \RealtimeUser.name
        case "age": return \RealtimeUser.age
        case "photo": return \RealtimeUser.photo
        case "groups": return \RealtimeUser.groups
        case "followers": return \RealtimeUser.followers
        case "ownedGroup": return \RealtimeUser.ownedGroup
        case "scheduledConversations": return \RealtimeUser.scheduledConversations
        default: return nil
        }
    }
}

let user = User(in: Node(key: "user_1"))
user.name <== "User name"
user.photo <== UIImage(named: "img")

let transaction = user.save(in: .root)
transaction.commit(with: { state, err in
    /// process error
})
```

### Properties

***ReadonlyRealtimeProperty*** - readonly stored property for any value.

***RealtimeProperty*** - stored property for any value.

***SharedRealtimeProperty*** - stored property similar `RealtimeProperty`, but uses concurrency transaction to update value. Use this property if value assumes shared access (for example 'number of likes' value).

### References

***RealtimeReference*** - stores reference on any database value. Doesn't imply referential integrity. Use it if record won't be removed or else other reason that doesn't need referential integrity.

***RealtimeRelation*** - stores reference on any database value. It creates link on side related object. On deletion related object will be deleted reference.

### Files

***ReadonlyStorageProperty*** - readonly stored property for file in Firebase Storage.

***StorageProperty*** - stored property for file in Firebase Storage.

### Collections
```swift
class Object: RealtimeObject {
    lazy var array: RealtimeArray<Object> = "some_array".array(from: self.node)
    lazy var linkedArray: LinkedRealtimeArray<Object> = "some_linked_array".linkedArray(from: self.node, elements: .root("linked_objects"))
    lazy var dictionary: RealtimeDictionary<Object> = "some_dictionary".dictionary(from: self.node, keys: .root("key_objects"))
}
```
All collections conform to protocol `RealtimeCollection`.
Collections are entities that require preparation before using. In common case you call one time for each collection object:
```swift
let users = RealtimeArray<User>(in: .root("users"))
users.prepare(forUse: { (users, err) in
    /// working with collection
})
```
But in mutable operations include auto preparation, that allows to avoid explicity call this method.

***LinkedRealtimeArray*** is array that stores objects as references.
Source elements must locate in the same reference. On insertion of object to this array creates link on side object.

***RealtimeArray*** is array that stores objects by value in itself location.

`LinkedRealtimeArray`, `RealtimeArray` mutating:
```swift
do {
    let transaction = RealtimeTransaction()
    ...
    let element = Element()
    try array.write(element: element, in: transaction)
    try otherArray.remove(at: 1, in: trasaction)

    transaction.commit { (err) in
        // process error

        self.tableView.reloadData()
    }
} catch let e {
    // process error
}
```

***RealtimeDictionary*** is dictionary where keys are references, but values are objects. On save value creates link on side key object.

`LinkedRealtimeDictionary`, `RealtimeDictionary` mutating:
```swift
do {
    let transaction = RealtimeTransaction()
    ...
    let element = Element() // you should take new element from target collection location
    try dictionary.write(element: element, key: key, in: transaction)
    try otherDictionary.remove(by: key, in: transaction)

    transaction.commit { (err) in
        // process error
    }
} catch let e {
    // process error
}
```

***KeyedRealtimeCollection*** *(Deprecated)* is immutable collection that gets elements from elements of base collection by specific key path. This is the result of x.keyed(by:elementBuilder:) method, where x is any RealtimeCollection. 
```swift
let userNames = RealtimeArray<User>(in: usersNode).keyed(by: Nodes.name)
```

***MapRealtimeCollection*** is immutable collection that gets elements from map function. This is the result of x.lazyMap(_ transform:) method, where x is any RealtimeCollection. 
```swift
let userNames = RealtimeArray<User>(in: usersNode).keyed(by: Nodes.name)
```

### Transactions

***RealtimeTransaction*** - object that contains all information about write transactions.
Almost all data changes perform using this object.
The most mutable operations just take transaction as parameter, but to create custom complex operations you can use this methods:
```swift
/// adds operation of save RealtimeValue as single value
func set<T: RealtimeValue & RealtimeValueEvents>(_ value: T, by node: Node)
/// adds operation of delete RealtimeValue
func delete<T: RealtimeValue & RealtimeValueEvents>(_ value: T)
/// adds operation of update RealtimeValue
func update<T: ChangeableRealtimeValue & RealtimeValueEvents & Reverting>(_ value: T)
/// method to merge actions of other transaction
func merge(_ other: RealtimeTransaction)
```
For more details see Example project.

### UI

***SingleSectionTableViewDelegate*** -  provides single section data source for UITableView with auto update.
***SectionedTableViewDelegate*** -  provides sectioned data source for UITableView with auto update.

### Local listening

To receive changes on local level use objects that conform this protocol.
```swift
public protocol Listenable {
    associatedtype OutData

    /// Disposable listening of value
    func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<OutData>) -> Disposable

    /// Listening with possibility to control active state
    func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<OutData>) -> ListeningItem
}
```

## Limitions
Implementation didn't test on multithread, and doesn't guarantee stable working on non main thread.

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

Xcode 9+, Swift 4.1+.

## Installation

Realtime is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'Realtime'
```

## Author

Koryttsev Denis, koden.u8800@gmail.com

## License

Realtime is available under the MIT license. See the LICENSE file for more info.
