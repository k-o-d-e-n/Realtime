//
//  FormViewController.swift
//  Realtime_Example
//
//  Created by Denis Koryttsev on 08/09/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import UIKit
import Realtime

class TextCell: UITableViewCell {
    var listenings: [Disposable] = []
    lazy var titleLabel: UILabel = self.textLabel!.add(to: self.contentView)
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            titleLabel.removeObserver(self, forKeyPath: "text")
        } else {
            titleLabel.addObserver(self, forKeyPath: "text", options: [], context: nil)
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
    override init(style: UITableViewCell.CellStyle = .value1, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

let defaultCellIdentifier = "default"
let textInputCellIdentifier = "input"
let valueCellIdentifier = "value"

class FormViewController: UITableViewController {
    let store = ListeningDisposeStore()
    var form: Form<User>!

    deinit {
        print("deinit \(self)")
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
            args.view.titleLabel.text = "Name"
            args.view.textField.text <== args.model.name
            args.view.textField.realtime
                .onEvent(.editingDidEnd)
                .map({ $0.0.text })
                .compactMap()
                .listening(onValue: { (text) in
                    args.1.name <== text
                })
                .add(to: row.disposeStorage)
        }
        let age: Row<TextCell, User> = Row(reuseIdentifier: textInputCellIdentifier)
        age.onUpdate { (args, row) in
            args.view.titleLabel.text = "Age"
            args.view.textField.keyboardType = .numberPad
            args.view.textField.text = args.model.age.wrappedValue.map(String.init)
            args.view.textField.realtime
                .onEvent(.editingDidEnd)
                .map({ $0.0.text })
                .flatMap(UInt8.init)
                .map { $0 ?? 0 }
                .listening(onValue: { (age) in
                    args.1.age <== age
                })
                .add(to: row.disposeStorage)
        }
        let photo: Row<UITableViewCell, User> = Row(reuseIdentifier: defaultCellIdentifier)
        photo.onUpdate { (args, row) in
            args.view.textLabel?.text = "Pick image"
            args.model.photo
                .flatMap()
                .flatMap(UIImage.init)
                .listening(onValue: { args.view.imageView?.image = $0 })
                .add(to: row.disposeStorage)
        }
        photo.onSelect({ [weak self] (ip, row) in
            let picker = UIImagePickerController()
            picker.realtime.image
                .map({ (args) -> UIImage in
                    guard case let originalImage as UIImage = args.1[.originalImage] else {
                        throw NSError()
                    }
                    return originalImage
                })
                .listening(onValue: { [unowned row] (originalImage) in
                    row.model?.photo <== originalImage.pngData()
                    row.view?.setNeedsLayout()
                })
                .add(to: row.disposeStorage)
            self?.present(picker, animated: true, completion: nil)
        })

        let ownedGroup: Row<SubtitleCell, User> = Row(reuseIdentifier: valueCellIdentifier)
        ownedGroup.onUpdate { (args, row) in
            args.view.accessoryType = .disclosureIndicator
            args.view.textLabel?.text = "Owned group"
            args.model.ownedGroup
                .then({ $0?.name })
                .listening(onValue: { args.view.detailTextLabel?.text = $0 })
                .add(to: row.disposeStorage)
        }
        ownedGroup.onSelect({ [weak self] (_, row) in
            self?.pickOwnedGroup(row)
        })

        let section = StaticSection<User>(headerTitle: "Regular fields", footerTitle: nil)
        section.addRow(name)
        section.addRow(age)
        section.addRow(photo)
        section.addRow(ownedGroup)

        let followers = ReuseRowSection<User, User>(
            ReuseRowSectionDataSource(collection: Global.rtUsers),
            cell: { tv, ip in tv.dequeueReusableCell(withIdentifier: defaultCellIdentifier, for: ip) },
            row: FormViewController.followerRow
        )
        followers.headerTitle = "Followers"

        let user = User()
        self.form = Form(model: user, sections: [section, followers])
        form.tableView = tableView
        form.tableDelegate = self

        user.name.flatMap()
            .combine(with: user.age.flatMap())
            .map({ (val) -> Bool in
                switch val {
                case (let name?, let age?):
                    return !name.isEmpty && age != 0
                default:
                    return false
                }
            })
            .listening(onValue: { [unowned self] (isEnabled) in
                self.navigationItem.rightBarButtonItem?.isEnabled = isEnabled
            })
            .add(to: store)
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

    private func pickOwnedGroup(_ row: Row<SubtitleCell, User>) {
        let delegate = SingleSectionTableViewDelegate(Global.rtGroups, cell: { (tv, ip, _) -> UITableViewCell in
            return tv.dequeueReusableCell(withIdentifier: NSStringFromClass(UITableViewCell.self), for: ip)
        })
        delegate.register(UITableViewCell.self, binding: { (item, _, group, ip) in
            item.bind(group.name, { (cell, name) in
                cell.textLabel?.text <== name
            }, nil)
        })
        let groupPicker = PickTableViewController(delegate: delegate)
        groupPicker.didSelect = { [unowned row] _,_, group in
            row.model?.ownedGroup <== group
            row.model?.ownedGroups.insert(element: group)
            row.view?.setNeedsLayout()
            Global.rtGroups.stopObserving()
            return (true, nil)
        }
        groupPicker.onDismiss = Global.rtGroups.changes.listening(onValue: { (event) in
            groupPicker.tableView.reloadData()
        }).dispose
        Global.rtGroups.runObserving()
        groupPicker.title = "Groups"
        present(UINavigationController(rootViewController: groupPicker), animated: true, completion: nil)
    }

    private static func followerRow() -> ReuseFormRow<UITableViewCell, User, User> {
        let row: ReuseFormRow<UITableViewCell, User, User> = ReuseFormRow()
        row.onRowModel({ (user, row) in
            row.view?.textLabel?.text <== user.name
            row.bind(user.name, { (cell, name) in
                cell.textLabel?.text <== name
            }, nil)
        })
        row.onSelect({ (ip, row) in
            guard let c = row.view, let user = row.model else { return }

            let isAdded = c.accessoryType == .none
            c.accessoryType = isAdded ? .checkmark : .none
            let follower = Global.rtUsers[ip.row]
            let contains = user.followers.contains(follower)
            if isAdded, !contains {
                user.followers.insert(element: follower)
            } else if contains {
                user.followers.delete(element: follower)
            }
        })
        return row
    }
}

extension FormViewController {
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { tableView.sectionHeaderHeight }
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { 0.0 }
}

