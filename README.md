# Realtime

[![CI Status](http://img.shields.io/travis/k-o-d-e-n/Realtime.svg?style=flat)](https://travis-ci.org/k-o-d-e-n/Realtime)
[![Version](https://img.shields.io/cocoapods/v/Realtime.svg?style=flat)](http://cocoapods.org/pods/Realtime)
[![License](https://img.shields.io/cocoapods/l/Realtime.svg?style=flat)](http://cocoapods.org/pods/Realtime)
[![Platform](https://img.shields.io/cocoapods/p/Realtime.svg?style=flat)](http://cocoapods.org/pods/Realtime)

Realtime is database framework based on Firebase that makes the creation of complex database structures is simple. :exclamation: (Alpha version)
Realtime can help you to create app quicker than if use clear Firebase API herewith to apply complex structures to store data in Firebase database, to update UI using reactive behaviors.
Realtime provides lightweight data traffic, lazy initialization of data, good distribution of data.

## Features

:point_right:  **Simple scalable model structure**

:point_right:  **Collections**

:point_right:  **References**

:point_right:  **UI support**

Implementation based on myself designed reactive structures. `(don't ask me why I didn't use RxSwift, just didn't want :ok_hand:)`

## Usage

### Model

To create any model data structure you can make by subclassing `RealtimeObject`.
You can define child properties using classes:
+ `RealtimeObject` subclasses;
+ `RealtimeProperty` (typealias `StandartProperty`);
+ `LinkedRealtimeArray`, `RealtimeArray`, `RealtimeDictionary`;
Also for auto decoding you need implement class function `keyPath(for:)`.
This function called for each subclass, therefore you don't need call super implementation. 
Example:
```swift
class User: RealtimeObject {
    lazy var name: StandartProperty<String?> = "user_name".property(from: self.dbRef)

    open class func keyPath(for label: String) -> AnyKeyPath? {
        switch label {
            case "name": return \User.name
            default: return nil
        }
    }
}
```

### Properties

***RealtimeProperty*** - stored property for any value.
For system types (such as Bool, Int, String, Array, Dictionary) you can use `typealias StandartProperty`. For custom types you need implement serializer conformed to protocol `_Serializer`.

***SharedRealtimeProperty*** - stored property similar `RealtimeProperty`, but uses concurrency transaction to update value. Use this property if value assumes shared access (for example 'like' value). :exclamation: Not implemented yet.

### References

***LinkedRealtimeProperty*** - stores reference on any database value. Doesn't imply referential integrity. Use it if record won't be removed or else other reason that doesn't need referential integrity.

***RealtimeRelation*** - stores reference on any database value. It creates link on side related object. On deletion related object will be deleted reference.

### Collections
All collections conform to protocol `RealtimeCollection`.

***LinkedRealtimeArray*** is array that stores objects as references.
Source elements must located in the same reference. On insertion of object to this array creates link on side object.

***RealtimeArray*** is array that stores objects by value in itself location.

***RealtimeDictionary*** is dictionary where keys are references, but values are objects. On save value creates link on side key object.

***LinkedRealtimeDictionary*** is collection like as `RealtimeDictionary`, but values store by reference. :exclamation: Not implemented yet.

***KeyedRealtimeArray*** is collection that gets elements from elements of base collection by specific key path. This is the result of x.keyed(by:elementBuilder:) method where x is any RealtimeCollection.

```swift
class Object: RealtimeObject {
    lazy var array: RealtimeArray<Object> = "some_array".array(from: self.dbRef)
    lazy var linkedArray: LinkedRealtimeArray<Object> = "some_linked_array".linkedArray(from: self.dbRef, elements: .fromRoot("linked_objects"))
    lazy var dictionary: RealtimeDictionary<Object> = "some_dictionary".dictionary(from: self.dbRef, keys: .fromRoot("key_objects"))
    lazy var linkedDictionary: RealtimeDictionary<Object> = "some_linked_dictionary".linkedDictionary(from: self.dbRef, keys: .fromRoot("key_objects"), values: .fromRoot("value_objects"))
}
```

### Transactions

***RealtimeTransaction*** - object that contains all information about write transactions.
Almost all data changes perform using this object.

### UI

***RealtimeTableAdapter***

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



## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

Xcode 9+, Swift 4+.

## Installation

Realtime is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'Realtime'
```

## Author

k-o-d-e-n, koden.u8800@gmail.com

## License

Realtime is available under the MIT license. See the LICENSE file for more info.
