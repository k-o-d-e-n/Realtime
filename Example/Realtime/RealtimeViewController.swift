//
//  RealtimeViewController.swift
//  SaladBar
//
//  Created by Denis Koryttsev on 16/02/2018.
//  Copyright © 2018 Stamp. All rights reserved.
//

import UIKit
import Realtime

protocol LazyLoadable {}
extension NSObject: LazyLoadable {}
extension LazyLoadable where Self: UIView {
    func add(to superview: UIView) -> Self {
        superview.addSubview(self); return self
    }
    func add(to superview: UIView, completion: (Self) -> Void) -> Self {
        superview.addSubview(self); completion(self); return self
    }
}

class RealtimeViewController: UIViewController {
    lazy var addUserButton: UIButton! = UIButton(type: .system).add(to: view) {
        $0.frame = CGRect(x: 0, y: 0,
                          width: view.bounds.width / 2, height: 30)
        $0.setTitle("Add user", for: .normal)
    }
    lazy var removeUserButton: UIButton! = UIButton(type: .system).add(to: view) {
        $0.frame = CGRect(x: view.bounds.width / 2, y: 0,
                          width: view.bounds.width / 2, height: 30)
        $0.setTitle("Remove user", for: .normal)
    }
    lazy var addGroupButton: UIButton! = UIButton(type: .system).add(to: view) {
        $0.frame = CGRect(x: 0, y: 30,
                          width: view.bounds.width / 2, height: 30)
        $0.setTitle("Add group", for: .normal)
    }
    lazy var removeGroupButton: UIButton! = UIButton(type: .system).add(to: view) {
        $0.frame = CGRect(x: view.bounds.width / 2, y: 30,
                          width: view.bounds.width / 2, height: 30)
        $0.setTitle("Remove group", for: .normal)
    }
    lazy var addConversationButton: UIButton! = UIButton(type: .system).add(to: view) {
        $0.frame = CGRect(x: 0, y: 60, width: view.bounds.width / 2, height: 30)
        $0.setTitle("Add conversation", for: .normal)
    }
    lazy var removeConversationButton: UIButton! = UIButton(type: .system).add(to: view) {
        $0.frame = CGRect(x: view.bounds.width / 2, y: 60, width: view.bounds.width / 2, height: 30)
        $0.setTitle("Remove conversation", for: .normal)
    }
    lazy var linkButton: UIButton! = UIButton(type: .system).add(to: view) {
        $0.frame = CGRect(x: 0, y: 90, width: view.bounds.width / 2, height: 30)
        $0.setTitle("Link group and user", for: .normal)
    }
    lazy var unlinkButton: UIButton! = UIButton(type: .system).add(to: view) {
        $0.frame = CGRect(x: view.bounds.width / 2, y: 90, width: view.bounds.width / 2, height: 30)
        $0.setTitle("Unlink group and user", for: .normal)
    }

    lazy var label: UILabel! = UILabel().add(to: view) {
        $0.frame = CGRect(x: 20, y: view.bounds.height - 100, width: view.bounds.width, height: 30)
        $0.text = "Result here"
    }
    var user: RealtimeUser? {
        didSet { user?.groups.runObserving() }
    }
    var group: RealtimeGroup? {
        didSet { group?.users.runObserving(); group?.conversations.runObserving() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        edgesForExtendedLayout.remove(.top)

        Global.rtUsers.prepare(forUse: .just { (users, _) in
            self.user = users.first
        })
        Global.rtGroups.prepare(forUse: .just { (groups, err) in
            self.group = groups.first
        })

        addUserButton.addTarget(self, action: #selector(addUser), for: .touchUpInside)
        removeUserButton.addTarget(self, action: #selector(removeUser), for: .touchUpInside)
        addGroupButton.addTarget(self, action: #selector(addGroup), for: .touchUpInside)
        removeGroupButton.addTarget(self, action: #selector(removeGroup), for: .touchUpInside)
        addConversationButton.addTarget(self, action: #selector(addConversation), for: .touchUpInside)
        removeConversationButton.addTarget(self, action: #selector(removeConversation), for: .touchUpInside)
        linkButton.addTarget(self, action: #selector(linkUserGroup), for: .touchUpInside)
        unlinkButton.addTarget(self, action: #selector(unlinkUserGroup), for: .touchUpInside)
    }

    @objc func addUser() {
        let transaction = RealtimeTransaction()

        let user = RealtimeUser()
        user.name <= "userName"
        user.age <= 100

        try! Global.rtUsers.write(element: user, in: transaction)

        transaction.commit(with: { (_, error) in
            self.user = user

            if let error = error {
                debugPrint(error)
                return
            }

            self.label.text = error?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
        })
    }

    @objc func addGroup() {
        let transaction = RealtimeTransaction()

        let group = RealtimeGroup()
        group.name <= "groupName"

        try! Global.rtGroups.write(element: group, in: transaction)

        transaction.commit(with: { (_, error) in
            self.group = group

            if let error = error {
                debugPrint(error)
                return
            }

            self.label.text = error?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
        })
    }

    @objc func removeUser() {
        guard let ref = user?.node ?? Global.rtUsers.first?.node else { return }
        let u = RealtimeUser(in: ref)

        let controller = UIAlertController(title: "", message: "Remove using:", preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: "Collection", style: .default) { (_) in
            let transaction = Global.rtUsers.remove(element: u)

            transaction?.commit { _, errs in
                if let errors = errs {
                    print(errors)
                } else {
                    assert(!Global.rtUsers.contains(u))
                    if let g = self.group {
                        assert(!g.users.contains(u))
                    }
                }

                self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
            }
        })
        controller.addAction(UIAlertAction(title: "Object", style: .default) { (_) in
            u.delete().commit { _, errs in
                if let errors = errs {
                    print(errors)
                } else {
//                    assert(!Global.rtUsers.contains(u))
                    if let g = self.group {
                        assert(!g.users.contains(u))
                    }
                }

                self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
            }
        })
        present(controller, animated: true, completion: nil)
    }

    @objc func removeGroup() {
        guard let ref = group?.node ?? Global.rtGroups.first?.node else { return }
        let grp = RealtimeGroup(in: ref)

        let controller = UIAlertController(title: "", message: "Remove using:", preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: "Collection", style: .default) { (_) in
            let transaction = Global.rtGroups.remove(element: grp)

            transaction?.commit { _, errs in
                if let errors = errs {
                    print(errors)
                } else {
                    assert(!Global.rtGroups.contains(grp))
                    if let u = self.user {
                        assert(!u.groups.contains(grp))
                    }
                }

                self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
            }
        })
        controller.addAction(UIAlertAction(title: "Object", style: .default) { (_) in
            grp.delete().commit { _, errs in
                if let errors = errs {
                    print(errors)
                } else {
//                    assert(!Global.rtGroups.contains(grp))
                    if let u = self.user {
                        assert(!u.groups.contains(grp))
                    }
                }

                self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
            }
        })
        present(controller, animated: true, completion: nil)
    }

    @objc func linkUserGroup() {
        guard let u = user ?? Global.rtUsers.first, let g = group ?? Global.rtGroups.first else { fatalError() }

        let ug = try! u.groups.write(element: g)
        let gu = try! g.users.write(element: u)

        let transaction = RealtimeTransaction()
        u.ownedGroup.setValue(g, in: transaction)
        transaction.merge(ug)
        transaction.merge(gu)
        transaction.commit { _, errs in
            if let errors = errs {
                print(errors)
            } else {
                assert(u.groups.contains(g))
                assert(g.users.contains(u))
            }

            self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
        }
    }

    @objc func unlinkUserGroup() {
        guard let u = user ?? Global.rtUsers.first, let g = group ?? Global.rtGroups.first else { fatalError() }

        let controller = UIAlertController(title: "", message: "Unlink user/group?", preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: "User", style: .default) { (_) in
            let transaction = g.users.remove(element: u)
            u.ownedGroup.setValue(nil, in: transaction)

            transaction?.commit { _, errs in
                if let errors = errs {
                    print(errors)
                } else {
                    assert(!g.users.contains(u))
                }

                self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
            }
        })
        controller.addAction(UIAlertAction(title: "Group", style: .default) { (_) in
            let transaction = u.groups.remove(element: g)
            g.manager.setValue(nil, in: transaction)

            transaction?.commit { _, errs in
                if let errors = errs {
                    print(errors)
                } else {
                    assert(!u.groups.contains(g))
                }

                self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
            }
        })
        present(controller, animated: true, completion: nil)
    }

    @objc func addConversation() {
        guard let u = user ?? Global.rtUsers.first, let g = group ?? Global.rtGroups.first else { fatalError() }

        var conversationUser = RealtimeUser()
        conversationUser.name <= "Conversation #"
        let transaction = try! g.conversations.write(element: conversationUser, for: u)

        transaction.commit { _, errs in
            if let errors = errs {
                print(errors)
            } else {
                assert(g.conversations.contains(valueBy: u))
            }

            self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
        }
    }

    @objc func removeConversation() {
        guard let u = user ?? Global.rtUsers.first, let g = group ?? Global.rtGroups.first else { fatalError() }

        let controller = UIAlertController(title: "", message: "Remove using:", preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: "Collection", style: .default) { (_) in
            let transaction = g.conversations.remove(for: u)

            transaction?.commit { _, errs in
                if let errors = errs {
                    print(errors)
                } else {
                    assert(!g.conversations.contains(valueBy: u))
                }

                self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
            }
        })
        controller.addAction(UIAlertAction(title: "Object", style: .default) { (_) in
            g.conversations.runObserving()
            g.conversations.prepare(forUse: .just { (convers, err) in
                guard err == nil else {
                    if let error = err {
                        print(error)
                        self.label.text = err?.localizedDescription
                    }
                    return
                }

                convers.first?.value.delete().commit { _, errs in
                    if let errors = errs {
                        print(errors)
                    } else {
                        assert(!g.conversations.contains(valueBy: u))
                    }

                    self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
                }
            })
        })
        present(controller, animated: true, completion: nil)
    }
}
