# Realtime

[![Version](https://img.shields.io/cocoapods/v/Realtime.svg?style=flat)](http://cocoapods.org/pods/Realtime)
[![License](https://img.shields.io/cocoapods/l/Realtime.svg?style=flat)](http://cocoapods.org/pods/Realtime)
[![Platform](https://img.shields.io/cocoapods/p/Realtime.svg?style=flat)](http://cocoapods.org/pods/Realtime)

Realtime is ORM framework that makes the creation of complex database structures is simple.

## Features

:point_right:  **Simple scalable model structure**

:point_right: **Files**

:point_right:  **Collections**

:point_right:  **References**

:point_right:  **UI, Form**

### Support Firebase Database
Firebase Realtime Database is fully supported and uses in production.
If you use clean Firebase API, Realtime can help to create app quicker, herewith to apply complex structures to store data, to update UI using reactive behaviors.
Realtime provides lightweight data traffic, lazy initialization of data, good distribution of data.

### Support FoundationDB
FoundationDB is supported, but with some limitations, because FDB has no native observing mechanisms.

## Usage

### Initialization

In `AppDelegate` in `func application(_:didFinishLaunchingWithOptions:)` you must call code below, to configure working environment.
Now for cache policy is valid values `case .noCache, .persistance` only. Cache in memory is not implemented yet.
```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    /// ...

    /// initialize Realtime
    RealtimeApp.initialize(...)

    ///...
    return true
}
```

### Model

To create any model data structure you can make by subclassing `Object`.
You can define child properties using classes:
+ `Object` subclasses;
+ `ReadonlyProperty`, `Property`, `Reference`, `Relation`, `ReadonlyFile`, `File`;
+ `References`, `Values`, `AssociatedValues`, and so on;
If you use lazy properties, you need implement class function `lazyPropertyKeyPath(for:)`. (Please tell me if you know how avoid it, without inheriting NSObject).
This function called for each subclass, therefore you don't need call super implementation. 
Example:
```swift
class User: Object {
    lazy var name: Property<String> = "name".property(in: self)
    lazy var age: Property<Int> = "age".property(in: self)
    lazy var photo: File<UIImage?> = "photo".file(in: self, representer: .png)
    lazy var groups: References<RealtimeGroup> = "groups".references(in: self, elements: .groups)
    lazy var scheduledConversations: Values<Conversation> = "scheduledConversations".values(in: self)
    lazy var ownedGroup: Relation<RealtimeGroup?> = "ownedGroup".relation(in: self, "manager")

    override class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "name": return \User.name
        case "age": return \User.age
        case "photo": return \User.photo
        case "groups": return \User.groups
        case "ownedGroup": return \User.ownedGroup
        case "scheduledConversations": return \User.scheduledConversations
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

***ReadonlyProperty*** - readonly stored property for any value.

***Property*** - stored property for any value.

***SharedProperty*** - stored property similar `Property`, but uses concurrency transaction to update value. Use this property if value assumes shared access (for example 'number of likes' value).

### References

***Reference*** - stores reference on any database value. Doesn't imply referential integrity. Use it if record won't be removed or else other reason that doesn't need referential integrity.

***Relation*** - stores reference on any database value. It creates link on side related object. On deletion related object will be deleted reference.

### Files

***ReadonlyFile*** - readonly stored property for file in Firebase Storage.

***File*** - stored property for file in Firebase Storage.

### Collections
```swift
class Some: Object {
    lazy var array: Values<Object> = "some_array".values(in: self)
    lazy var references: References<Object> = "some_linked_array".references(in: self, elements: .linkedObjects)
    lazy var dictionary: AssociatedValues<Object> = "some_dictionary".dictionary(in: self, keys: .keyObjects)
}
```
Some mutable operations of collections can require `isSynced` state. To achieve this state use `func runObserving()` function or set property `keepSynced: Bool` to `true`.

***References*** is array that stores objects as references.
Source elements must locate in the same reference. On insertion of object to this array creates link on side object.

***Values*** is array that stores objects by value in itself location.

`References`, `Values` mutating:
```swift
do {
    let transaction = Transaction()
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

***AssociatedValues*** is dictionary where keys are references, but values are objects. On save value creates link on side key object.

`AssociatedValues` mutating:
```swift
do {
    let transaction = Transaction()
    ...
    let element = Element()
    try dictionary.write(element: element, key: key, in: transaction)
    try otherDictionary.remove(by: key, in: transaction)

    transaction.commit { (err) in
        // process error
    }
} catch let e {
    // process error
}
```

***MapRealtimeCollection*** is immutable collection that gets elements from map function. This is the result of x.lazyMap(_ transform:) method, where x is any RealtimeCollection. 
```swift
let userNames = Values<User>(in: usersNode).lazyMap { user in
    return user.name
}
```

### Operators

+ `<==`  - assignment operator. Can use to assign (or to retrieve) value to (from) any Realtime property.
+ `====`, `!===` - comparison operators. Can use to compare any Realtime properties where their values conform to `Equatable` protocol.
+ `??` - infix operator, that performs a nil-coalescing operation, returning the wrapped value of an Realtime property or a default value.
+ `<-` - prefix operator. Can use to convert instance of `Closure, Assign` types to explicit closure or backward.

### Transactions

***Transaction*** - object that contains all information about write transactions.
Almost all data changes perform using this object.
The most mutable operations just take transaction as parameter, but to create custom complex operations you can use this methods:
```swift
/// adds operation of save RealtimeValue as single value as is
func set<T: RealtimeValue & RealtimeValueEvents>(_ value: T, by node: Node)
/// adds operation of delete RealtimeValue
func delete<T: RealtimeValue & RealtimeValueEvents>(_ value: T)
/// adds operation of update RealtimeValue
func update<T: ChangeableRealtimeValue & RealtimeValueEvents & Reverting>(_ value: T)
/// method to merge actions of other transaction
func merge(_ other: Transaction)
```
For more details see Example project.

### UI

***SingleSectionTableViewDelegate*** -  provides single section data source for UITableView with auto update.
***SectionedTableViewDelegate*** -  provides sectioned data source for UITableView with auto update.
***CollectionViewDelegate*** - provides data source for UICollectionView with auto update.
```swift
delegate.register(UITableViewCell.self) { (item, cell, user, ip) in
    item.bind(
        user.name, { cell, name in
            cell.textLabel?.text = name 
        }, 
        { err in
            print(err)
        }
    )
}
delegate.bind(tableView)
delegate.tableDelegate = self

// data
users.changes
    .listening(
        onValue: { [weak tableView] (e) in
            guard let tv = tableView else { return }
            switch e {
            case .initial: tv.reloadData()
            case .updated(let deleted, let inserted, let modified, let moved):
                tv.beginUpdates()
                tv.insertRows(at: inserted.map({ IndexPath(row: $0, section: 0) }), with: .automatic)
                tv.deleteRows(at: deleted.map({ IndexPath(row: $0, section: 0) }), with: .automatic)
                tv.reloadRows(at: modified.map({ IndexPath(row: $0, section: 0) }), with: .automatic)
                moved.forEach { from, to in
                    tv.moveRow(at: IndexPath(row: from, section: 0), to: IndexPath(row: to, section: 0))
                }
                tv.endUpdates()
            }
        },
        onError: onError
    )
    .add(to: listeningCollector)
```

### Forms

```swift
class User: Object {
    var name: Property<String>
    var age: Property<Int>
}

class FormViewController: UIViewController {
    var form: Form<User>

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let name = Row<TextCell, Model>.inputRow(
            "input",
            title: Localized.name,
            keyboard: .name,
            placeholder: .inputPlaceholder(Localized.name),
            onText: { $0.name <== $1 }
        )
        name.onUpdate { (args, row) in
            args.view.textField.text <== args.model.name
        }
        let age = Row<TextCell, Model>.inputRow(
            "input",
            title: Localized.age,
            keyboard: .numberPad,
            placeholder: requiredPlaceholder,
            onText: { $0.age <== $1 }
        )
        age.onUpdate { (args, row) in
            args.view.textField.text <== args.model.age
        }
        let button: Row<ButtonCell, Model> = Row(reuseIdentifier: "button")
        button.onUpdate { (args, row) in
            args.view.titleLabel.text = Localized.login
        }
        button.onSelect { [unowned self] (_, row) in
            self.submit()
        }

        let fieldsSection: StaticSection<Model> = StaticSection(headerTitle: nil, footerTitle: nil)
        fieldsSection.addRow(name)
        fieldsSection.addRow(age)

        let buttonSection: StaticSection<Model> = StaticSection(headerTitle: nil, footerTitle: nil)
        buttonSection.addRow(button)

        form = Form(model: User(), sections: [fieldsSection, buttonSection])
        form.tableView = tableView
        form.tableDelegate = self
    }
}
```

### Local listening

To receive changes on local level use objects that conform this protocol. It has similar RxSwift interface.
```swift
public protocol Listenable {
    associatedtype OutData

    /// Disposable listening of value
    func listening(_ assign: Assign<OutData>) -> Disposable
}
```

### Debugging
Add debug argument 'REALTIME_CRASH_ON_ERROR' passed on launch, to catch internal errors.

### JS
Also exists NodeJS module, created for Vue.js application. Source code you can found in `js` folder.

## Limitations
Realtime objects should not passed between threads.

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

Xcode 9+, Swift 4.1+.

## Installation

SwiftPM
```swift
    .package(url: "https://github.com/k-o-d-e-n/realtime.git", .branch("master"))
```

Realtime is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'Realtime'
```

## Author

Koryttsev Denis, koden.u8800@gmail.com
Twitter: [@K_o_D_e_N](https://twitter.com/K_o_D_e_N)

## License

Realtime is available under the MIT license. See the LICENSE file for more info.
