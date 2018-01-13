//
//  ViewController.swift
//  Realtime
//
//  Created by k-o-d-e-n on 01/11/2018.
//  Copyright (c) 2018 k-o-d-e-n. All rights reserved.
//

import UIKit
import Realtime

class Object: RealtimeObject {
    lazy var id: StandartProperty<String?> = self.register(prop: "id".property(from: self.dbRef))
    lazy var array: RealtimeArray<Object> = self.register(prop: "array".array(from: self.dbRef))
}

class ViewController: UIViewController {
    var disposeBag = ListeningDisposeStore()
    let node = RealtimeNode(rawValue: "node")

    override func viewDidLoad() {
        super.viewDidLoad()
        var logo = AsyncReadonlyProperty<String?>(value: nil) { (setter) in
        }

        _ = logo.insider.listen(.just { print($0 as Any) })
        _ = logo.insider.listen(as: { $0.queue(.main) }, .guarded(self) { _, _ in

        })
        var count = 0
        _ = logo.insider.listen(as: { $0.livetime(self) }, preprocessor: { $0.map { $0!.count } }, .just {
            count = $0
        })
        print(count)

        let object = Object(dbRef: .root())
        object.id.listening(Assign.guarded(self) { (v, o) in

        }.on(queue: .main)).add(to: &disposeBag)
        object.id.listeningItem(.on(.main) { v in

        }).add(to: &disposeBag)

        object.array.contains(object)
    }
}

