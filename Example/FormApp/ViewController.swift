//
//  ViewController.swift
//  FormApp
//
//  Created by Denis Koryttsev on 08.06.2021.
//  Copyright © 2021 CocoaPods. All rights reserved.
//

import UIKit
import Combine
import RealtimeForm

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

class TableViewCell: UITableViewCell {
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView?.image = nil
        textLabel?.text = nil
        detailTextLabel?.text = nil
        accessoryView = nil
        accessoryType = .none
    }
}

class TextCell: UITableViewCell {
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

class SubtitleCell: TableViewCell {
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

    override func prepareForReuse() {
        super.prepareForReuse()
        hideIndicator()
    }

    func hideIndicator() {
        detailTextLabel?.isHidden = false
        activityIndicator.stopAnimating()
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Publisher where Self.Failure == Never {
    func assign<Root, Cell>(to keyPath: ReferenceWritableKeyPath<Root, Self.Output>, on object: Root, undoManager: UndoManager, row: Row<Cell, Root>, undoRow: @escaping (Cell, Output) -> Void) -> AnyCancellable
    where Root: AnyObject {
        handleEvents(receiveOutput: { _ in
            undoManager.beginUndoGrouping()
            let oldValue = object[keyPath: keyPath]
            undoManager.registerUndo(withTarget: object) { target in
                target[keyPath: keyPath] = oldValue
                row.view.map({ undoRow($0, oldValue) })
            }
            undoManager.endUndoGrouping()
        })
        .assign(to: keyPath, on: object)
    }
}

let defaultCellIdentifier = "default"
let textInputCellIdentifier = "input"
let valueCellIdentifier = "value"

@available(iOS 13.4, *)
class ViewController: UITableViewController {
    class Model {
        var account: String?

        var name: String?
        var birthdate: Date?
        var gender: Gender?

        var pet: Animal?
        var petColor: UIColor?

        @Published var attachments: [String] = []

        var accepted: Bool = false

        struct Gender: SelectViewControllerModel {
            var id: String
            let title: String
        }
        struct Animal: SelectViewControllerModel {
            var id: String
            let title: String
        }
    }
    var cancels: [AnyCancellable] = []
    var form: Form<Model>!

    private var genderOptions = [
        Model.Gender(id: "🙍‍♂️", title: "🙍‍♂️ Male"),
        Model.Gender(id: "🙍‍♀️", title: "🙍‍♀️ Female"),
        Model.Gender(id: "🤖", title: "🤖 Other")
    ]
    private let animalOptions = [
        Model.Animal(id: "🐴", title: "🐴 Horse"),
        Model.Animal(id: "🐢", title: "🐢 Turtle"),
        Model.Animal(id: "🐶", title: "🐶 Dog"),
        Model.Animal(id: "🐱", title: "🐱 Cat"),
        Model.Animal(id: "🐭", title: "🐭 Mouse"),
        Model.Animal(id: "🦆", title: "🦆 Duck")
    ]

    class AttachmentsDataSource: DynamicSectionDataSource {
        let model: ViewController.Model
        var changes: AnyPublisher<DynamicSectionEvent, Never> {
            model.$attachments
                .scan((oldValue: model.attachments, newValue: model.attachments)) { storage, newValue in
                    (storage.1, newValue)
                }
                .filter({ $0.oldValue.count != $0.newValue.count })
                .map({ old, new -> DynamicSectionEvent in
                    let diff = new.difference(from: old)
                    var insertions: [Int] = []
                    var deletions: [Int] = []
                    for change in diff {
                        switch change {
                        case .insert(let offset, _, _): insertions.append(offset)
                        case .remove(let offset, _, _): deletions.append(offset)
                        }
                    }
                    return .updated(deleted: deletions, inserted: insertions, modified: [], moved: [])
                })
                .receive(on: DispatchQueue.main)
                .eraseToAnyPublisher()
        }
        var keepSynced: Bool { get { true } set {} }
        var count: Int { model.attachments.count + 1 }
        subscript(index: Int) -> RowValue {
            model.attachments.count > index ? .element(model.attachments[index]) : .actionButton
        }

        enum RowValue {
            case element(String)
            case actionButton
        }

        init(_ model: ViewController.Model) {
            self.model = model
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Form"
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Print", style: .done, target: self, action: #selector(printModel)),
            UIBarButtonItem(barButtonSystemItem: .undo, target: self, action: #selector(undo)),
            UIBarButtonItem(title: "Reset", style: .plain, target: self, action: #selector(reset))
        ]
        navigationItem.largeTitleDisplayMode = .always
        tableView.backgroundView = UIView()
        tableView.backgroundView?.backgroundColor = .systemGroupedBackground
        tableView.keyboardDismissMode = .onDrag
        tableView.tableFooterView = UIView()
        tableView.register(TableViewCell.self, forCellReuseIdentifier: defaultCellIdentifier)
        tableView.register(TextCell.self, forCellReuseIdentifier: textInputCellIdentifier)
        tableView.register(SubtitleCell.self, forCellReuseIdentifier: valueCellIdentifier)
        #if targetEnvironment(macCatalyst)
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        #endif

        let model = Model()

        let accounts = DynamicSection<Model, String>(AnyCollectionDataSource(["Twitter", "Telegram", "Facebook"])) { tv, ip, _ in
            tv.dequeueReusableCell(withIdentifier: defaultCellIdentifier, for: ip)
        }
        accounts.headerTitle = "Accounts"
        accounts.register(TableViewCell.self) { row, cell, model, ip in
            cell.textLabel?.text = model
        }
        accounts.selectPublisher()
            .sink { (form, row, acc) in
                form.model.account = acc
            }
            .store(in: &cancels)

        let profile = StaticSection<Model>(headerTitle: "Profile", footerTitle: nil)
        let name: Row<TextCell, Model> = Row(reuseIdentifier: textInputCellIdentifier)
        name.onSelect { event, row in
            row.view?.textField.becomeFirstResponder()
        }
        /*/// Closure approach
        name.onUpdate { update, row in
            update.view.imageView?.image = UIImage(systemName: "person")
            update.view.titleLabel.text = "Name"
            update.view.textField.text = update.model.name
            update.view.textField
                .publisher(for: \.text, options: .new)
                .assign(to: \.name, on: update.model)
                .store(in: &row.disposeStorage)
        }
        */
        /// Publisher approach
        name.updatePublisher()
            .handleEvents(receiveOutput: { update, row in
                update.view.imageView?.image = UIImage(systemName: "person")
                update.view.titleLabel.text = "Name"
                update.view.textField.text = update.model.name
            })
            .flatMap(maxPublishers: .max(1), { update, _ in
                update.view.textField
                    .publisher(for: \.text, options: .new)
                    .combineLatest(Just(update.model))
            })
            .sink(receiveValue: { $1.name = $0 })
            .store(in: &cancels)
        profile.addRow(name)
        let birthdate: Row<UITableViewCell, Model> = Row(reuseIdentifier: defaultCellIdentifier)
        let datePicker: UIDatePicker = UIDatePicker()
        datePicker.maximumDate = Date()
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        birthdate.onSelect { event, row in
            if row.model?.birthdate == nil {
                row.model?.birthdate = datePicker.date
            }
        }
        birthdate.onUpdate { [unowned self] update, row in
            update.view.imageView?.image = UIImage(systemName: "calendar")
            update.view.textLabel?.text = "Birthdate"
            update.view.accessoryView = datePicker
            datePicker.publisher(for: UIControl.Event.valueChanged)
                .map({ $0.0.date })
                .assign(
                    to: \.birthdate,
                    on: update.model,
                    undoManager: self.undoManager!,
                    row: row,
                    undoRow: { ($0.accessoryView as? UIDatePicker)?.date = $1 ?? Date() }
                )
                .store(in: &row.disposeStorage)
        }
        profile.addRow(birthdate)
        let gender: Row<UITableViewCell, Model> = Row(reuseIdentifier: defaultCellIdentifier)
        let segmentedControl = UISegmentedControl(items: genderOptions.map({ $0.title }))
        gender.onUpdate { [unowned self] update, row in
            update.view.accessoryView = segmentedControl
            update.view.textLabel?.text = "Gender"
            segmentedControl.publisher(for: UIControl.Event.valueChanged)
                .map({ self.genderOptions[$0.0.selectedSegmentIndex] })
                .assign(
                    to: \.gender, on: update.model,
                    undoManager: self.undoManager!,
                    row: row,
                    undoRow: { ($0.accessoryView as? UISegmentedControl)?.selectedSegmentIndex = $1.flatMap(genderOptions.firstIndex(of:)) ?? UISegmentedControl.noSegment }
                )
                .store(in: &row.disposeStorage)
        }
        profile.addRow(gender)

        let pet = StaticSection<Model>(headerTitle: "Animal", footerTitle: nil)
        let animal: Row<SubtitleCell, Model> = Row(reuseIdentifier: valueCellIdentifier)
        animal.onUpdate { update, row in
            update.view.imageView?.image = UIImage(systemName: "tortoise")
            update.view.textLabel?.text = "Pet"
            update.view.detailTextLabel?.text = update.model.pet?.title
            update.view.accessoryType = .disclosureIndicator
        }
        animal.onSelect { [unowned self] event, row in
            let animalPicker = SelectViewController(models: animalOptions, selectedModels: row.model?.pet.map({ [$0] }) ?? [])
            animalPicker.didSelect = { vc, _, value in
                row.model?.pet = value
                row.view?.detailTextLabel?.text = value.title
                vc.navigationController?.popViewController(animated: true)
            }
            self.navigationController?.pushViewController(animalPicker, animated: true)
        }
        pet.addRow(animal)
        if #available(iOS 14.0, *) {
            let color: Row<UITableViewCell, Model> = Row(reuseIdentifier: defaultCellIdentifier)
            color.onUpdate { update, row in
                update.view.imageView?.image = UIImage(systemName: "eyedropper")
                update.view.accessoryView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 30, height: 30)))
                update.view.accessoryView?.layer.cornerRadius = 6
                update.view.accessoryView?.layer.borderWidth = 2
                update.view.accessoryView?.layer.borderColor = UIColor.lightGray.withAlphaComponent(0.2).cgColor
                update.view.textLabel?.text = "Color"
                update.view.accessoryView?.backgroundColor = update.model.petColor
            }
            color.onSelect { [unowned self] event, row in
                let colorPicker = UIColorPickerViewController()
                colorPicker.view.backgroundColor = .systemGroupedBackground
                colorPicker.publisher(for: \.selectedColor, options: .new)
                    .map { $0 }
                    .handleEvents(receiveOutput: {
                        row.view?.accessoryView?.backgroundColor = $0
                    })
                    .assign(
                        to: \.petColor, on: row.model!,
                        undoManager: self.undoManager!,
                        row: row,
                        undoRow: { $0.accessoryView?.backgroundColor = $1 }
                    )
                    .store(in: &row.disposeStorage)
                self.present(colorPicker, animated: true)
            }
            pet.addRow(color)
        }

        let attachmentsDataSource = AttachmentsDataSource(model)
        let attachments = DynamicSection<Model, AttachmentsDataSource.RowValue>(attachmentsDataSource) { tv, ip, _ in
            tv.dequeueReusableCell(withIdentifier: valueCellIdentifier, for: ip)
        }
        attachments.headerTitle = "Attachments"
        attachments.register(SubtitleCell.self) { row, cell, model, ip in
            switch model {
            case .element(let name):
                cell.imageView?.image = UIImage(systemName: "\(ip.row).circle")
                cell.textLabel?.text = name
            case .actionButton:
                cell.imageView?.image = UIImage(systemName: "plus.circle")
                cell.textLabel?.text = "Add attachment"
            }
        }
        attachments.selectPublisher()
            .sink { (form, row, rowModel) in
                guard case .actionButton = rowModel else { return }
                form.model.attachments.append("Attachment #\(form.model.attachments.count)")
            }
            .store(in: &cancels)
        /// footer view
        /*let addAttachment = UIButton()
        addAttachment.setTitle("Add", for: .normal)
        addAttachment.setTitleColor(.black, for: .normal)
        addAttachment.setImage(UIImage(systemName: "plus.circle"), for: .normal)
        addAttachment.addTarget(self, action: #selector(ViewController.addAttachment), for: .touchUpInside)
        attachments.setFooterRow(Row(static: addAttachment))*/

        let terms: StaticSection<Model> = StaticSection(
            headerTitle: "Terms",
            footerTitle: "By accessing or using this website and related services, you agree to these Terms and Conditions, which include our Privacy Policy (Terms)."
        )
        let actions: StaticSection<Model> = StaticSection(headerTitle: nil, footerTitle: nil)

        let acception: Row<UITableViewCell, Model> = Row(reuseIdentifier: defaultCellIdentifier)
        let switchControl = UISwitch()
        acception.onUpdate { [unowned self] update, row in
            update.view.textLabel?.text = "I agree to the terms & conditions"
            update.view.imageView?.image = UIImage(systemName: "signature")
            update.view.accessoryView = switchControl
            switchControl.publisher(for: UIControl.Event.valueChanged)
                .map({ $0.control.isOn })
                .handleEvents(receiveOutput: { isOn in
                    self.form.beginUpdates()
                    if isOn {
                        self.form.addSection(actions, with: .fade)
                    } else {
                        self.form.deleteSections(at: [self.form.numberOfSections - 1], with: .fade)
                    }
                    self.form.endUpdates()
                })
                .assign(to: \.accepted, on: update.model)
                .store(in: &row.disposeStorage)
        }
        terms.addRow(acception)

        let action: Row<SubtitleCell, Model> = Row(reuseIdentifier: valueCellIdentifier)
        action.onSelect { event, row in
            row.view?.showIndicator()
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) {
                row.view?.hideIndicator()
            }
        }
        action.onUpdate { update, row in
            update.view.imageView?.image = UIImage(systemName: "applelogo")
            update.view.textLabel?.text = "Sign up"
            update.view.textLabel?.textAlignment = .center
        }
        actions.addRow(action)

        form = Form(model: model, sections: [accounts, profile, pet, attachments, terms])
        form.tableView = tableView
        form.tableDelegate = self
        form.editingDataSource = self
        tableView.sectionFooterHeight = UITableView.automaticDimension
    }

    var _undoManager: FormUndoManager = FormUndoManager()
    override var undoManager: UndoManager? { _undoManager }
    override var canBecomeFirstResponder: Bool { true }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resignFirstResponder()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        undoManager?.groupsByEvent = false
        undoManager?.beginUndoGrouping()
    }

    final class FormUndoManager: UndoManager {
        var nestedGroupCount: Int?
        var canUndoNestedGroup: Bool { nestedGroupCount.map({ $0 > 0 }) == true }

        override func beginUndoGrouping() {
            if groupingLevel == 1 {
                if let count = nestedGroupCount {
                    nestedGroupCount = count + 1
                } else {
                    nestedGroupCount = 1
                }
            }
            super.beginUndoGrouping()
        }
        override func endUndoGrouping() {
            if groupingLevel == 1 {
                nestedGroupCount = nil
            }
            super.endUndoGrouping()
        }
    }
    @objc func undo() {
        if _undoManager.canUndoNestedGroup {
            undoManager?.undoNestedGroup()
            navigationItem.rightBarButtonItems?[1].isEnabled = _undoManager.canUndoNestedGroup
        }
    }
    @objc func reset() {
        undoManager?.endUndoGrouping()
        undoManager?.undo()
    }
    @objc func printModel() {
        var output = ""
        dump(form.model, to: &output)
        print(output)
    }
    /*@objc func addAttachment() {
        form.model.attachments.append("Attachment \(form.model.attachments.count)")
    }*/

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { false }
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        self.tableView(tableView, canEditRowAt: indexPath) ? .delete : .none
    }
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == 3 && indexPath.row < tableView.numberOfRows(inSection: 3) - 1
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        switch editingStyle {
        case .delete: form.model.attachments.remove(at: indexPath.row)
        default: break
        }
    }
}
@available(iOS 13.4, *)
extension ViewController: UITableViewEditingDataSource {}

@available(iOS 13.0, *)
public extension Combine.Publishers {
    /// A Control Event is a publisher that emits whenever the provided
    /// Control Events fire.
    struct ControlEvent<Control: UIControl>: Publisher {
        public typealias Output = (control: Control, event: UIEvent)
        public typealias Failure = Never

        private let control: Control
        private let controlEvents: Control.Event

        /// Initialize a publisher that emits a Void
        /// whenever any of the provided Control Events trigger.
        ///
        /// - parameter control: UI Control.
        /// - parameter events: Control Events.
        public init(control: Control,
                    events: Control.Event) {
            self.control = control
            self.controlEvents = events
        }

        public func receive<S: Subscriber>(subscriber: S) where S.Failure == Failure, S.Input == Output {
            let subscription = Subscription(subscriber: subscriber,
                                            control: control,
                                            event: controlEvents)

            subscriber.receive(subscription: subscription)
        }
    }
}

// MARK: - Subscription
@available(iOS 13.0, *)
extension Combine.Publishers.ControlEvent {
    private final class Subscription<S: Subscriber, Control: UIControl>: Combine.Subscription where S.Input == (control: Control, event: UIEvent) {
        private var subscriber: S?
        private weak var control: Control?

        init(subscriber: S, control: Control, event: Control.Event) {
            self.subscriber = subscriber
            self.control = control
            control.addTarget(self, action: #selector(handleEvent), for: event)
        }

        func request(_ demand: Subscribers.Demand) {
            // We don't care about the demand at this point.
            // As far as we're concerned - UIControl events are endless until the control is deallocated.
        }

        func cancel() {
            subscriber = nil
        }

        @objc private func handleEvent(_ control: UIControl, event: UIEvent) {
            _ = subscriber?.receive((unsafeDowncast(control, to: Control.self), event))
        }
    }
}

protocol UIControlEventPublisher {}

@available(iOS 13.0, *)
extension UIControlEventPublisher where Self: UIControl {
    /// A publisher emitting events from this control.
    func publisher(for events: UIControl.Event) -> Publishers.ControlEvent<Self> {
        Publishers.ControlEvent(control: self, events: events)
    }
}
extension UIControl: UIControlEventPublisher {}

protocol SelectViewControllerModel: Equatable {
    associatedtype ID : Hashable
    var id: Self.ID { get }
    var image: UIImage? { get }
    var title: String { get }
}
extension SelectViewControllerModel {
    var image: UIImage? { nil }
}
extension SelectViewControllerModel {
    static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

class SelectViewController<Model>: UITableViewController where Model: SelectViewControllerModel {
    let models: [Model]
    var selectedModels: [Model]

    var didSelect: ((SelectViewController<Model>, IndexPath, Model) -> Void)?

    required init(models: [Model], selectedModels: [Model]) {
        self.models = models
        self.selectedModels = selectedModels
        super.init(style: .plain)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        tableView.keyboardDismissMode = .onDrag
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { models.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        let model = models[indexPath.row]
        cell.imageView?.image = model.image
        cell.textLabel?.text = model.title
        cell.accessoryType = selectedModels.contains(model) ? .checkmark : .none
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let model = models[indexPath.row]
        didSelect?(self, indexPath, model)
        tableView.cellForRow(at: indexPath)?.accessoryType = selectedModels.contains(model) ? .checkmark : .none
    }
}
