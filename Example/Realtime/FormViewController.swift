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
    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indView = UIActivityIndicatorView(style: .gray)
        contentView.addSubview(indView)
        return indView
    }()

    override init(style: UITableViewCell.CellStyle = .value1, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    func showIndicator() {
        activityIndicator.startAnimating()
        detailTextLabel?.isHidden = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if detailTextLabel?.isHidden == true {
            let offset: CGFloat = accessoryType != .none ? 0 : 15
            activityIndicator.center = CGPoint(x: contentView.frame.width - offset - activityIndicator.frame.width/2, y: contentView.center.y)
        }
    }

    func hideIndicator() {
        detailTextLabel?.isHidden = false
        activityIndicator.stopAnimating()
    }
}

let defaultCellIdentifier = "default"
let textInputCellIdentifier = "input"
let valueCellIdentifier = "value"

extension Listenable {
    func runMap<U>(_ transformer: @escaping (Out) -> () -> U) -> Preprocessor<Self, U> {
        map({
            transformer($0)()
        })
    }
    func dynamicDispatch<Obj: NSObject>(to obj: Obj, action: Selector, _ error: ((Error) -> Void)? = nil) -> Disposable {
        listening({ [weak obj] (event) in
            switch event {
            case .value(let v):
                if let o = obj {
                    o.perform(action, with: v)
                }
            case .error(let e):
                error?(e)
            }
        })
    }
}
extension Listenable {
    func filterLocal<T>() -> Preprocessor<Self, Out> where Self.Out == PropertyState<T> {
        filter { (state) -> Bool in
            switch state {
            case .local: return false
            default: return true
            }
        }
    }
}

class FormViewController: UITableViewController {
    let store = ListeningDisposeStore()
    let transaction = Transaction()
    var form: Form<User>!
    let editingUser: User?

    init(user: User? = nil) {
        self.editingUser = user
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        print("deinit \(self)")
        if !transaction.isInvalidated {
            transaction.revert()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = "User form"
        if editingUser != nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Reset", style: .plain, target: self, action: #selector(resetUser))
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(saveUser))
        navigationItem.rightBarButtonItem?.isEnabled = false

        tableView.keyboardDismissMode = .onDrag
        tableView.tableFooterView = UIView()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: defaultCellIdentifier)
        tableView.register(TextCell.self, forCellReuseIdentifier: textInputCellIdentifier)
        tableView.register(SubtitleCell.self, forCellReuseIdentifier: valueCellIdentifier)

        let user = editingUser ?? User()

        let name: Row<TextCell, User> = Row(reuseIdentifier: textInputCellIdentifier)
        name.mapUpdate()
            .then({ $0.0.view.textField.realtime.onEvent(.editingChanged) })
            .map({ $0.0.text ?? "" })
            .bind(to: user.name)
            .add(to: store)
        name.mapUpdate()
            .combine(with: user.name.filterLocal().flatMap())
            .listening { (update, name) in
                update.0.view.textField.text = name
            }
            .add(to: store)
        name.onUpdate { (args, row) in
            args.view.titleLabel.text = "Name"
        }
        name.onSelect { (ctx, row) in
            row.view?.textField.becomeFirstResponder()
        }
        let age: Row<TextCell, User> = Row(reuseIdentifier: textInputCellIdentifier)
        age.mapUpdate()
            .combine(with: user.age.filterLocal().flatMap(String.init))
            .listening { (update, age) in
                update.0.view.textField.text = age
            }
            .add(to: store)
        age.onUpdate { (args, row) in
            args.view.titleLabel.text = "Age"
            args.view.textField.keyboardType = .numberPad
        }
        age.mapUpdate()
            .then({ $0.0.view.textField.realtime.onEvent(.editingDidEnd) })
            .map({ $0.0.text })
            .flatMap(UInt8.init)
            .map { $0 ?? 0 }
            .bind(to: user.age)
            .add(to: store)
        age.onSelect { (ctx, row) in
            row.view?.textField.becomeFirstResponder()
        }
        let photo: Row<UITableViewCell, User> = Row(reuseIdentifier: defaultCellIdentifier)
        photo.onUpdate { (args, row) in
            args.view.textLabel?.text = "Pick image"
        }
        photo.mapUpdate()
            .combine(with: user.photo.flatMap().flatMap(UIImage.init))
            .listening(onValue: { (update, image) in
                update.0.view.imageView?.image = image
                update.0.view.setNeedsLayout()
            })
            .add(to: store)
        photo.mapSelect()
            .then { [weak self] (ctx, row) -> UIImagePickerController.ImagePicker in
                let picker = UIImagePickerController()
                defer { self?.present(picker, animated: true, completion: nil) }
                return picker.realtime.image
            }
            .map({ (args) -> UIImage in
                guard case let originalImage as UIImage = args.1[.originalImage] else {
                    throw NSError()
                }
                return originalImage
            })
            .runMap(UIImage.pngData)
            .bind(to: user.photo)
            .add(to: store)

        let ownedGroup: Row<SubtitleCell, User> = Row(reuseIdentifier: valueCellIdentifier)
        ownedGroup.editingStyle = UITableViewCell.EditingStyle.delete
        ownedGroup.onUpdate { (args, row) in
            args.view.accessoryType = .disclosureIndicator
            args.view.textLabel?.text = "Owned group"
        }
        ownedGroup
            .mapUpdate()
            .do(onValue: { $0.0.view.showIndicator() })
            .then({ (args, row) in
                args.model.ownedGroup.loadValue().then { $0.name.loadValue() }.map { ($0, args.view) }
            })
            .listening(onValue: { name, cell in
                cell.hideIndicator()
                cell.detailTextLabel?.text = name
            })
            .add(to: store)
        ownedGroup.onSelect { [weak self] (_, row) in
            self?.pickOwnedGroup(row)
        }

        let section = StaticSection<User>(headerTitle: "Regular fields", footerTitle: nil)
        section.addRow(name)
        section.addRow(age)
        section.addRow(photo)
        section.addRow(ownedGroup)

        let followers = ReuseRowSection<User, User>(
            ReuseRowSectionDataSource(collection: Global.rtUsers),
            cell: { tv, ip in tv.dequeueReusableCell(withIdentifier: defaultCellIdentifier, for: ip) },
            row: followerRow(editingUser)
        )
        followers.headerTitle = "Followers"

        self.form = Form(model: user, sections: [section, followers])
        form.tableView = tableView
        form.tableDelegate = self
        form.editingDataSource = self

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

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { true }
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { false }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        switch editingStyle {
        case .delete:
            if form.model.ownedGroup.hasChanges {
                let currentGroup = form.model.ownedGroup.unwrapped
                form.model.ownedGroup.revert()
                if let group = currentGroup {
                    if form.model.isRooted {
                        form.model.ownedGroups.remove(element: group, in: transaction)
                    } else {
                        form.model.ownedGroups.delete(element: group)
                    }
                }
            }
        default: break
        }
    }

    @objc func resetUser() {
        form.model.revert()
    }

    @objc func saveUser() {
        let alert = showWaitingAlert()
        do {
            if form.model.isRooted {
                try form.model.update(in: transaction)
            } else {
                try Global.rtUsers.write(element: form.model, in: transaction)
            }
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
        groupPicker.didSelect = { [unowned row, unowned transaction] _,_, group in
            guard let model = row.model else { fatalError() }
            model.ownedGroup <== group
            if model.isRooted {
                try! model.ownedGroups.write(group, in: transaction)
            } else {
                model.ownedGroups.insert(element: group)
            }
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

    private func followerRow(_ currentUser: User?) -> () -> ReuseFormRow<UITableViewCell, User, User> {
        return { [unowned transaction] in
            let row: ReuseFormRow<UITableViewCell, User, User> = ReuseFormRow()
            row.onRowModel({ (user, row) in
                row.view?.alpha = currentUser == user ? 0.5 : 1
                row.view?.textLabel?.text <== user.name
                row.bind(user.name, { (cell, name) in
                    cell.textLabel?.text <== name
                }, nil)
            })
            row.onSelect({ (ctx, row) in
                guard let c = row.view, let user = row.model else { return }

                let isAdded = c.accessoryType == .none
                c.accessoryType = isAdded ? .checkmark : .none
                let follower = Global.rtUsers[ctx.indexPath.row]
                let contains = user.followers.contains(follower)
                if isAdded, !contains {
                    if user.isRooted {
                        try! user.followers.write(follower, in: transaction)
                    } else {
                        user.followers.insert(element: follower)
                    }
                } else if contains {
                    if user.isRooted {
                        user.followers.remove(element: follower, in: transaction)
                    } else {
                        user.followers.delete(element: follower)
                    }
                }
            })
            return row
        }
    }
}

extension FormViewController: RealtimeEditingTableDataSource {
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { tableView.sectionHeaderHeight }
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { 0.0 }
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        form[indexPath.section][indexPath.row].editingStyle ?? .none
    }
}

