//
//  FormViewController.swift
//  Realtime_Example
//
//  Created by Denis Koryttsev on 08/09/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import Foundation
import Realtime

class Label: UILabel {
    var didSet: Repeater<String?> = .unsafe()
    override var text: String? {
        didSet {
            didSet.send(.value(text))
        }
    }
}

class TextCell: UITableViewCell {
    var listenings: [Disposable] = []
    lazy var titleLabel: UILabel = self.textLabel!.add(to: self.contentView) { label in
        label.addObserver(self, forKeyPath: "text", options: [], context: nil)// TODO: strong reference cycle
//        listenings.append(
//            label.didSet
//                .distinctUntilChanged()
//                .listening(onValue: Closure.guarded(self, assign: { _, this in this.setNeedsLayout() }))
//
//        )
    }
    lazy var textField: UITextField = UITextField().add(to: self.contentView) { textField in
        textField.autocorrectionType = .default
        textField.autocapitalizationType = .sentences
        textField.keyboardType = .default
    }

    override var isSelected: Bool {
        didSet {
            if isSelected {
                textField.becomeFirstResponder()
            }
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "text" {
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel.sizeToFit()
        titleLabel.frame.origin = CGPoint(x: max(layoutMargins.left, separatorInset.left), y: (frame.height - titleLabel.font.lineHeight) / 2)
        textField.frame = CGRect(x: titleLabel.frame.maxX + 10, y: (frame.height - 30) / 2, width: frame.width - titleLabel.frame.maxX - 10, height: 30)
    }
}

class SubtitleCell: UITableViewCell {
    override init(style: UITableViewCellStyle = .value1, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

let defaultCellIdentifier = "default"
let textInputCellIdentifier = "input"
let valueCellIdentifier = "value"

class FormViewController: UIViewController {
    var store = ListeningDisposeStore()
    var delegate: SingleSectionTableViewDelegate<User>!
    var tableView: UITableView! { return view as! UITableView }

    var form: Form<User>!
    var validator: Accumulator<(String?, Int?)>!

    deinit {
        print("deinit \(self)")
    }

    override func loadView() {
        view = UITableView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = "User form"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(saveUser))
        navigationItem.rightBarButtonItem?.isEnabled = false

        tableView.keyboardDismissMode = .onDrag
        tableView.tableFooterView = UIView()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: defaultCellIdentifier)
        tableView.register(TextCell.self, forCellReuseIdentifier: textInputCellIdentifier)
        tableView.register(SubtitleCell.self, forCellReuseIdentifier: valueCellIdentifier)

        let name: Row<TextCell, User> = Row(reuseIdentifier: textInputCellIdentifier)
        name.onUpdate { (args, row) in
            args.0.titleLabel.text = "Name"
            args.0.textField.text <== args.1.name
            args.0.textField.realtime
                .onEvent(.editingDidEnd)
                .map({ $0.0.text })
                .compactMap()
                .listeningItem(onValue: { (text) in
                    args.1.name <== text
                })
                .add(to: row.disposeStorage)
        }
        let age: Row<TextCell, User> = Row(reuseIdentifier: textInputCellIdentifier)
        age.onUpdate { (args, row) in
            args.0.titleLabel.text = "Age"
            args.0.textField.keyboardType = .numberPad
            args.0.textField.text = args.1.age.wrapped.map(String.init)
            args.0.textField.realtime
                .onEvent(.editingDidEnd)
                .map({ $0.0.text })
                .flatMap(Int.init)
                .map { $0 ?? 0 }
                .listeningItem(onValue: { (age) in
                    args.1.age <== age
                })
                .add(to: row.disposeStorage)
        }
        let photo: Row<UITableViewCell, User> = Row(reuseIdentifier: defaultCellIdentifier)
        photo.onUpdate { [weak self] (args, row) in
            let (cell, user) = args
            cell.textLabel?.text = "Pick image"
            cell.imageView?.image = args.1.photo.unwrapped
            row.onSelect({ (ip, row) in
                let picker = UIImagePickerController()
                picker.realtime.image.listeningItem(onValue: { [unowned row] (args) in
                    guard case let originalImage as UIImage = args.1[UIImagePickerControllerOriginalImage] else {
                        fatalError()
                    }
                    user.photo <== originalImage
                    row.view?.imageView?.image = originalImage
                    row.view?.setNeedsLayout()
                }).add(to: row.disposeStorage)
                self?.present(picker, animated: true, completion: nil)
            })
        }

        let ownedGroup: Row<SubtitleCell, User> = Row(reuseIdentifier: valueCellIdentifier)
        ownedGroup.onUpdate { [weak self] (args, row) in
            let (cell, user) = args
            cell.accessoryType = .disclosureIndicator
            cell.textLabel?.text = "Owned group"
            cell.detailTextLabel?.text = "none"
            row.onSelect({ (_, row) in
                let delegate = SingleSectionTableViewDelegate(Global.rtGroups, cell: { (tv, ip, _) -> UITableViewCell in
                    return tv.dequeueReusableCell(withIdentifier: NSStringFromClass(UITableViewCell.self), for: ip)
                })
                delegate.register(UITableViewCell.self, binding: { (item, group, ip) in
                    item.bind(group.name, { (cell, name) in
                        cell.textLabel?.text <== name
                    })
                })
                let groupPicker = PickTableViewController(delegate: delegate)
                groupPicker.didSelect = { [unowned row] _,_, group in
                    user.ownedGroup <== group
                    user.ownedGroups.insert(element: group)
                    row.view?.detailTextLabel?.text <== group.name
                    row.view?.setNeedsLayout()
                    Global.rtGroups.stopObserving()
                    return (true, nil)
                }
                groupPicker.onDismiss = Global.rtGroups.changes.listeningItem(onValue: { (event) in
                    groupPicker.tableView.reloadData()
                }).dispose
                Global.rtGroups.runObserving()
                groupPicker.title = "Groups"
                self?.present(UINavigationController(rootViewController: groupPicker), animated: true, completion: nil)
            })
        }

        let section = StaticSection<User>(headerTitle: "Regular fields", footerTitle: nil)
        section.addRow(name)
        section.addRow(age)
        section.addRow(photo)
        section.addRow(ownedGroup)

        let followers = ReuseRowSection<User, User>(Global.rtUsers, row: {
            let row: ReuseFormRow<UITableViewCell, User, User> = ReuseFormRow(reuseIdentifier: defaultCellIdentifier)
            row.onRowModel({ (user, row) in
                row.view?.textLabel?.text <== user.name
                row.bind(user.name, { (cell, name) in
                    cell.textLabel?.text <== name
                })
            })
            row.onUpdate { (args, row) in
                let (cell, user) = args
            }
            row.onSelect({ (ip, row) in
                row.view.map { c in
                    guard let user = row.model else { return }

                    let isAdded = c.accessoryType == .none
                    c.accessoryType = isAdded ? .checkmark : .none
                    let follower = Global.rtUsers[ip.row]
                    let contains = user.followers.contains(follower)
                    if isAdded, !contains {
                        user.followers.insert(element: follower)
                    } else if contains {
                        user.followers.delete(element: follower)
                    }
                }
            })
            return row
        })
        followers.headerTitle = "Followers"

        Global.rtUsers.changes.once().listeningItem(onValue: { [weak self] event in
            defer {
                Global.rtUsers.stopObserving()
            }
            guard let `self` = self else { return }

            self.tableView.beginUpdates()
            switch event {
            case .initial:
                self.tableView.reloadSections([1], with: .automatic)
            case .updated(let deleted, let inserted, let modified, let moved):
                self.tableView.insertRows(at: inserted.map { IndexPath(row: $0, section: 1) }, with: .automatic)
                self.tableView.deleteRows(at: deleted.map { IndexPath(row: $0, section: 1) }, with: .automatic)
                self.tableView.reloadRows(at: modified.map { IndexPath(row: $0, section: 1) }, with: .automatic)
                moved.forEach({ (move) in
                    self.tableView.moveRow(at: IndexPath(row: move.from, section: 1), to: IndexPath(row: move.to, section: 0))
                })
            }
            self.tableView.endUpdates()
        }).add(to: store)
        Global.rtUsers.runObserving()

        let user = User()
        self.form = Form(model: user, sections: [section, followers])
        form.tableView = tableView

        validator = Accumulator(repeater: .unsafe(), user.name.map { $0.wrapped }, user.age.map { $0.wrapped })
        validator.listening(onValue: { [unowned self] (val) in
            var isEnabled: Bool
            switch val {
            case (.some(let name), .some(let age)):
                isEnabled = !name.isEmpty && age != 0
            default:
                isEnabled = false
            }
            self.navigationItem.rightBarButtonItem?.isEnabled = isEnabled
        }).add(to: store)
    }

    @objc func saveUser() {
        let alert = showWaitingAlert()
        let transaction = Transaction()
        do {
            try Global.rtUsers.write(element: form.model, in: transaction)
            transaction.commit { [weak self] (state, errors) in
                if let err = errors?.first {
                    fatalError(err.localizedDescription)
                }

                print("User did save")
                alert.dismiss(animated: true, completion: {
                    self?.navigationController?.popViewController(animated: true)
                })
            }
        } catch let e {
            transaction.revert()
            fatalError(e.localizedDescription)
        }
    }
}

