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
    var store: ListeningDisposeStore = ListeningDisposeStore()
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
    lazy var loadPhoto: UIButton = UIButton(type: .system).add(to: view) {
        $0.frame = CGRect(x: 0, y: 120, width: view.bounds.width / 2, height: 30)
        $0.setTitle("Load photo", for: .normal)
    }
    lazy var label: UILabel! = UILabel().add(to: view) {
        $0.frame = CGRect(x: 20, y: view.bounds.height - 100, width: view.bounds.width, height: 30)
        $0.text = "Result here"
    }

    var user: User?
    var group: Group?
    var conversationUser: User?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        edgesForExtendedLayout.remove(.top)

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(free))

        Global.rtUsers.changes.listening(onValue: { [unowned self] _ in
            if self.user == nil {
                self.user = Global.rtUsers.first
            }
        }).add(to: store)
        Global.rtGroups.changes.listening(onValue: { [unowned self] _ in
            if self.group == nil {
                self.group = Global.rtGroups.first
            }
        }).add(to: store)

        addUserButton.addTarget(self, action: #selector(addUser), for: .touchUpInside)
        removeUserButton.addTarget(self, action: #selector(removeUser), for: .touchUpInside)
        addGroupButton.addTarget(self, action: #selector(addGroup), for: .touchUpInside)
        removeGroupButton.addTarget(self, action: #selector(removeGroup), for: .touchUpInside)
        addConversationButton.addTarget(self, action: #selector(addConversation), for: .touchUpInside)
        removeConversationButton.addTarget(self, action: #selector(removeConversation), for: .touchUpInside)
        linkButton.addTarget(self, action: #selector(linkUserGroup), for: .touchUpInside)
        unlinkButton.addTarget(self, action: #selector(unlinkUserGroup), for: .touchUpInside)
        loadPhoto.addTarget(self, action: #selector(loadUserPhoto), for: .touchUpInside)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Global.rtUsers.runObserving()
        Global.rtGroups.runObserving()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Global.rtUsers.stopObserving()
        Global.rtGroups.stopObserving()
    }

    @objc func free() {
        let free = Transaction()
        let testsNode = Node(key: "___tests", parent: .root)
        free.removeValue(by: testsNode)

        freeze()
        free.commit(with: { _, error in
            self.unfreeze()
            if let e = error?.first {
                self.setError(e.localizedDescription)
            } else {
                self.setSuccess()
            }
        })
    }

    @objc func addUser() {
        let transaction = Transaction()

        let user = User()
        user.name <== "userName"
        user.age <== 100

        try! Global.rtUsers.write(element: user, in: transaction)

        freeze()
        transaction.commit(with: { (_, error) in
            self.unfreeze()
            self.user = user

            if let error = error {
                debugPrint(error)
                return
            }

            if let err = error?.reduce("", { $0 + $1.localizedDescription }) {
                self.setError(err)
            } else {
                self.setSuccess()
            }
        })
    }

    @objc func addGroup() {
        let transaction = Transaction()

        let group = Group()
        group.name <== "groupName"

        try! Global.rtGroups.write(element: group, in: transaction)

        freeze()
        transaction.commit(with: { (_, error) in
            self.unfreeze()
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
        let u = User(in: ref)

        let controller = UIAlertController(title: "", message: "Remove using:", preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: "Collection", style: .default) { (_) in
            let transaction = Global.rtUsers.remove(element: u)

            self.freeze()
            transaction.commit(with: { _, errs in
                self.unfreeze()
                if let errors = errs {
                    print(errors)
                }

                self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
            })
        })
        controller.addAction(UIAlertAction(title: "Object", style: .default) { (_) in
            self.freeze()
            try! u.delete().commit(with: { _, errs in
                self.unfreeze()
                if let errors = errs {
                    print(errors)
                }

                self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
            })
        })
        present(controller, animated: true, completion: nil)
    }

    @objc func removeGroup() {
        guard let ref = group?.node ?? Global.rtGroups.first?.node else { return }
        let grp = Group(in: ref)

        let controller = UIAlertController(title: "", message: "Remove using:", preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: "Collection", style: .default) { (_) in
            let transaction = Global.rtGroups.remove(element: grp)

            self.freeze()
            transaction.commit(with: { _, errs in
                self.unfreeze()
                if let errors = errs {
                    print(errors)
                }

                self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
            })
        })
        controller.addAction(UIAlertAction(title: "Object", style: .default) { (_) in
            self.freeze()
            try! grp.delete().commit(with: { _, errs in
                self.unfreeze()
                if let errors = errs {
                    print(errors)
                }

                self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
            })
        })
        present(controller, animated: true, completion: nil)
    }

    @objc func linkUserGroup() {
        guard let u = user ?? Global.rtUsers.first, let g = group ?? Global.rtGroups.first else { fatalError() }

        let ug = try! u.groups.write(element: g)
        let gu = try! g.users.write(element: u)

        let transaction = Transaction()
        try! u.ownedGroup.setValue(g, in: transaction)
        try! transaction.merge(ug)
        try! transaction.merge(gu)
        freeze()
        transaction.commit(with: { _, errs in
            self.unfreeze()
            if let errors = errs {
                print(errors)
            }

            self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
        })
    }

    @objc func unlinkUserGroup() {
        guard let u = user ?? Global.rtUsers.first, let g = group ?? Global.rtGroups.first else { fatalError() }

        let controller = UIAlertController(title: "", message: "Unlink user/group?", preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: "User", style: .default) { (_) in
            let transaction = g.users.remove(element: u)
            try! u.ownedGroup.setValue(nil, in: transaction)

            self.freeze()
            transaction?.commit(with: { _, errs in
                self.unfreeze()
                if let errors = errs {
                    print(errors)
                }

                self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
            })
        })
        controller.addAction(UIAlertAction(title: "Group", style: .default) { (_) in
            let transaction = u.groups.remove(element: g)
            try! g.manager.setValue(nil, in: transaction)

            self.freeze()
            transaction?.commit(with: { _, errs in
                self.unfreeze()
                if let errors = errs {
                    print(errors)
                }

                self.label.text = errs?.reduce("", { $0 + $1.localizedDescription }) ?? "Success! Show your firebase console"
            })
        })
        present(controller, animated: true, completion: nil)
    }

    @objc func addConversation() {
        guard let u = user ?? Global.rtUsers.first, let g = group ?? Global.rtGroups.first else { fatalError() }

        let conversationUser = User()
        conversationUser.age <== 100
        conversationUser.name <== "Conversation #"
        self.conversationUser = conversationUser
        do {
            let transaction = try g.conversations.write(element: conversationUser, for: u)

            self.freeze()
            transaction.commit(with: { _, errs in
                self.unfreeze()
                if let errors = errs {
                    print(errors)
                }

                self.setMessage(with: errs)
            })
        } catch let e {
            setError(e.localizedDescription)
        }
    }

    @objc func removeConversation() {
        guard let u = user ?? Global.rtUsers.first, let g = group ?? Global.rtGroups.first else { fatalError() }

        let controller = UIAlertController(title: "", message: "Remove using:", preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: "Collection", style: .default) { (_) in
            let transaction = g.conversations.remove(for: u)

            self.freeze()
            transaction?.commit(with: { _, errs in
                self.unfreeze()
                if let errors = errs {
                    print(errors)
                }

                self.setMessage(with: errs)
            })
        })
        controller.addAction(UIAlertAction(title: "Object", style: .default) { (_) in
            guard let conv = self.conversationUser else { return self.setError("Couldn`t retrieve conversation") }
            do {
                self.freeze()
                try conv.delete().commit(with: { _, errs in
                    self.unfreeze()
                    if let errors = errs {
                        print(errors)
                    }

                    self.setMessage(with: errs)
                })
            } catch let e {
                self.unfreeze()
                self.setError(e.localizedDescription)
            }
        })
        present(controller, animated: true, completion: nil)
    }

    @objc func loadUserPhoto() {
        let picker = UIImagePickerController()
        picker.delegate = self

        present(picker, animated: true, completion: nil)
    }

    weak var alert: UIAlertController?
    func freeze() {
        self.alert = showWaitingAlert()
    }

    func unfreeze() {
        self.alert?.dismiss(animated: true, completion: nil)
        self.alert = nil
    }
}

extension RealtimeViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        picker.dismiss(animated: true, completion: nil)
        guard let u = user ?? Global.rtUsers.first else {
            setError("Cannot retrieve user")
            return
        }

        guard let originalImage = info[UIImagePickerControllerOriginalImage] as? UIImage else {
            setError("Image picking is failed")
            return
        }

        u.photo <== originalImage

        let update = try! u.update()
        update.commit(with: { _,_  in }, filesCompletion: { (results) in
            let errs = results.reduce(into: [Error]()) { (out, result) in
                switch result {
                case .error(_, let e):
                    out.append(e)
                default: break
                }
            }
            if !errs.isEmpty {
                self.setError(errs.reduce("", { $0 + $1.localizedDescription }))
            } else {
                self.setSuccess()
            }
        })
    }
}

extension UIViewController {
    func showWaitingAlert() -> UIAlertController {
        let alert = UIAlertController(title: "Please, wait...", message: "Operation in progress", preferredStyle: .alert)
        present(alert, animated: true, completion: nil)
        return alert
    }
}

extension RealtimeViewController {
    func setError(_ text: String) {
        label.textColor = UIColor.red.withAlphaComponent(0.5)
        label.text = text
    }
    static let succesText = "Success! Show your firebase console"
    func setSuccess() {
        label.textColor = UIColor.green.withAlphaComponent(0.5)
        if label.text?.hasPrefix(RealtimeViewController.succesText) ?? false {
            label.text = label.text?.appending(" !")
        } else {
            label.text = RealtimeViewController.succesText
        }
    }
    func setMessage(with errors: [Error]?) {
        if let errorTxt = errors?.reduce("", { $0 + $1.localizedDescription }) {
            setError(errorTxt)
        } else {
            setSuccess()
        }
    }
}
