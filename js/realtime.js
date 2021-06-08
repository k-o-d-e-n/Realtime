'use strict';

const dev = require("./dev/realtime-dev");
exports.Utilities = dev.Utilities;

function fatalError(condition, message) {
  if (condition) {
    throw Error(message);
  }
}

function debugLog(condition, ...theArgs) {
  if (process.env.NODE_ENV !== "production") {
    if (condition) {
      console.log(theArgs);
    }
  }
}
function debugWarn(condition, ...theArgs) {
  if (process.env.NODE_ENV !== "production") {
    if (condition) {
      console.warn(theArgs);
    }
  }
}
function debug(doit) {
  if (process.env.NODE_ENV === "development") {
    doit();
  }
}

// Realtime

function linksRef(ref) {
  return ref.root.child(dev.InternalKeys.links + "/" + dev.Utilities.rootPath(ref));
}

Number.fromSnapshot = function(snapshot) {
  return new Number(snapshot.val());
};
String.fromSnapshot = function(snapshot) {
  return new String(snapshot.val());
};

let reactivityEnvironment;
exports.setReactivityEnvironment = function(environment) {
  reactivityEnvironment = environment;
}

function isPrimitive(test) {
  return test !== Object(test);
}

class RealtimeValue {
  constructor(ref, { raw, payload } = {}) {
    fatalError(ref == null, "Reference cannot be null");
    Object.defineProperty(this, "$_ref_", {
      value: ref, // TODO: probably may use `path` module to manage reference
      configurable: true,
      writable: false,
      enumerable: false
    });
    Object.defineProperty(this, "$_observing_", {
      value: {},
      configurable: true,
      writable: true,
      enumerable: false
    });
    fatalError(
      raw ? !isPrimitive(raw) : false,
      `Raw value may be only primitive, ${raw}`
    );
    Object.defineProperty(this, "raw", {
      value: raw,
      configurable: true,
      writable: false,
      enumerable: false
    });
    fatalError(
      payload ? typeof payload != "object" : false,
      `Payload may be only object, ${payload}`
    );
    Object.defineProperty(this, "payload", {
      value: payload,
      configurable: true,
      writable: false,
      enumerable: false
    });
  }

  _isObserved(event) {
    return this.$_observing_[event] != null;
  }

  _observe(event) {
    return new Promise((resolve, reject) => {
      let observing = this.$_observing_[event];
      if (observing) {
        observing.counter += 1;
        resolve(this);
      } else {
        observing = {
          callback: this.$_ref_.on(
            event,
            snapshot => {
              this.apply(snapshot);
              resolve(this);
            },
            reject,
            this
          ),
          counter: 1
        };
        this.$_observing_[event] = observing;
      }
    });
  }

  _stopObserving(event) {
    let observing = this.$_observing_[event];
    if (observing) {
      observing.counter -= 1;
      if (observing.counter < 1) {
        this._forceStopObserving(event, observing);
      }
    }
  }

  _forceStopObserving(event, observing) {
    const eventObserving = observing || this.$_observing_[event];
    if (eventObserving) {
      this.$_ref_.off(event, eventObserving.callback, this);
      delete this.$_observing_[event];
    }
  }

  load() {
    return this.$_ref_.once(dev.DataEvents.value).then(this.apply.bind(this));
  }

  forceStopObserving() {
    this._forceStopObserving(dev.DataEvents.value);
    this._forceStopObserving(dev.DataEvents.childAdded);
    this._forceStopObserving(dev.DataEvents.childRemoved);
    this._forceStopObserving(dev.DataEvents.childChanged);
    this._forceStopObserving(dev.DataEvents.childMoved);
  }

  apply(snapshot) {
    // console.log("Apply", snapshot.val(), dev.Utilities.rootPath(snapshot.ref));
    return this;
  }

  willRemove(transaction, ancestor) {
    // subclasses
  }

  remove(transaction) {
    this.willRemove(transaction, this.ref.parent);
    transaction.addValue(dev.Utilities.rootPath(this.ref), null);
  }

  write(transaction) {}

  _writeSystemValues(transaction) {
    if (this.raw != undefined) {
      transaction.addValue(
        dev.Utilities.rootPath(this.ref.child(dev.InternalKeys.raw)),
        this.raw
      );
    }
    if (this.payload && Object.keys(this.payload).length != 0) {
      transaction.addValue(
        dev.Utilities.rootPath(this.ref.child(dev.InternalKeys.payload), this.payload)
      );
    }
  }

  get key() {
    return this.$_ref_.key;
  }

  get path() {
    return dev.Utilities.rootPath(this.$_ref_);
  }

  get ref() {
    return this.$_ref_;
  }

  generateParentObjectWith(parentKey, objClass, sliced, options) {
    const ref = dev.Utilities.refThatHasParentWith(parentKey, this.ref, sliced);
    if (!ref) return null;
    return new objClass.prototype.constructor(ref, options);
  }

  toJSON() {
    return this;
  }
}
RealtimeValue.prototype.updaterWith = function(database, storage) {
  return this.updater(new Transaction(database, storage));
};

RealtimeValue.fromSnapshot = function(snapshot) {
  let options = {};
  if (snapshot.hasChild(dev.InternalKeys.raw)) {
    options.raw = snapshot.child(dev.InternalKeys.raw).val();
  }
  if (snapshot.hasChild(dev.InternalKeys.payload)) {
    options.payload = snapshot.child(dev.InternalKeys.payload).val();
  }
  const instance = new this.prototype.constructor(snapshot.ref, options);
  instance.apply(snapshot);
  return instance;
};
exports.RealtimeValue = RealtimeValue;

// Properties

class Property extends RealtimeValue {
  constructor(
    ref,
    { val, optional = false, readonly = false, representer } = {}
  ) {
    super(ref);
    this.value = val; // TODO: remove?
    Object.defineProperty(this, "value", {
      value: val,
      writable: !readonly,
      enumerable: true,
      configurable: true
    });
    Object.defineProperty(this, "optional", {
      value: optional,
      writable: false,
      enumerable: false,
      configurable: true
    });
    Object.defineProperty(this, "readonly", {
      value: readonly,
      writable: false,
      enumerable: false,
      configurable: true
    });
    Object.defineProperty(this, "representer", {
      value: representer,
      writable: false,
      enumerable: false,
      configurable: true
    });
  }

  runObserving() {
    return this._observe(dev.DataEvents.value);
  }

  stopObserving() {
    return this._stopObserving(dev.DataEvents.value);
  }

  get isObserved() {
    return this._isObserved(dev.DataEvents.value);
  }

  updater(transaction) {
    return new Proxy(this, new PropertyUpdaterHandler(transaction));
  }

  write(transaction) {
    if (this.readonly) return;
    const value = this.encode(this.value);
    if (!this.representer && (value === undefined || value === null)) {
      if (this.optional) return;
      debug(() => {
        console.error("Required property must not be empty", this);
      });
      throw Error("Required property must not be empty");
    }
    this._write(value, transaction);
  }

  _write(value, transaction) {
    transaction.addValue(this.path, value);
  }

  encode(value) {
    return this.representer ? this.representer.encode(value) : value;
  }

  apply(snapshot) {
    debug(() => {
      debugWarn(
        !this.optional && !snapshot.exists(),
        "Get empty data for required property",
        dev.Utilities.rootPath(snapshot.ref),
        snapshot.val()
      );
    });
    this.value = this.representer
      ? this.representer.decode(snapshot)
      : snapshot.val();
    return this.value;
  }

  toJSON() {
    if (this.value instanceof RealtimeValue) {
      return this.value.toJSON();
    } else {
      return this.value;
    }
  }
}
Property.prototype.loadIfUndefined = function() {
  if (this.value === undefined) {
    return this.load();
  }
  return Promise.resolve(this.value);
};
Property.prototype.loadIfEmpty = function() {
  if (!this.value) {
    return this.load();
  }
  return Promise.resolve(this.value);
};
Property.prototype.map = function(transform) {
  if (this.value === undefined || this.value === null) return;
  return transform(this.value);
};
exports.Property = Property;

exports.Reference = class Reference extends Property {
  constructor(ref, options) {
    super(ref, options);
    Object.defineProperty(this, "aboutValue", {
      value: options.value,
      writable: false,
      enumerable: false,
      configurable: true
    });
  }

  encode(value) {
    if (value) {
      if (this.aboutValue.obsoleteMode) {
        return this.aboutValue.path
          ? dev.Utilities.dbPath(
              this.ref.root.child(this.aboutValue.path),
              value.ref
            )
          : value.path;
      }
      let representation = {};
      representation[dev.InternalKeys.source] = this.aboutValue.path
        ? dev.Utilities.dbPath(this.ref.root.child(this.aboutValue.path), value.ref)
        : value.path;
      let valuePayload = {};
      if (value.raw) {
        valuePayload[dev.InternalKeys.raw] = value.raw;
      }
      if (value.payload) {
        valuePayload[dev.InternalKeys.payload] = value.payload;
      }
      representation[dev.InternalKeys.value] = valuePayload;
      return representation;
    }
    return null;
  }

  apply(snapshot) {
    if (snapshot.exists()) {
      if (this.aboutValue.obsoleteMode) {
        return this.__setValueWithRef(snapshot.val());
      } else if (snapshot.hasChild(dev.InternalKeys.source)) {
        const snapVal = snapshot.val();
        const valueDescriptor = snapVal[dev.InternalKeys.value] || {};
        const raw = valueDescriptor[dev.InternalKeys.raw];
        const payload = valueDescriptor[dev.InternalKeys.payload];
        const src = snapVal[dev.InternalKeys.source];
        return this.__setValueWithRef(src, raw, payload);
      } else {
        throw Error("Unexpected reference value");
      }
    } else {
      this.value = null;
      return null;
    }
  }

  __setValueWithRef(src, raw, payload) {
    let v;
    if (this.aboutValue.path) {
      v = new this.aboutValue.class.prototype.constructor(
        this.$_ref_.root.child(this.aboutValue.path).child(src),
        { raw: raw, payload: payload }
      );
    } else {
      v = new this.aboutValue.class.prototype.constructor(
        this.$_ref_.root.child(src),
        { raw: raw, payload: payload }
      );
    }
    this.value = v;
    return v;
  }
}

exports.Relation = class Relation extends Property {
  constructor(ref, options) {
    super(ref, options);
    Object.defineProperty(this, "aboutValue", {
      value: options.value,
      writable: false,
      enumerable: false,
      configurable: true
    });
  }

  encode(value) {
    if (value) {
      let representation = {};
      representation[dev.InternalKeys.targetPath] = this.aboutValue.path
        ? dev.Utilities.dbPath(this.ref.root.child(this.aboutValue.path), value.ref)
        : value.path;
      representation[dev.InternalKeys.relatedProperty] =
        typeof this.aboutValue.property == "function"
          ? this.aboutValue.property(
              dev.Utilities.ancestorOnLevelUp(
                this.ref,
                this.aboutValue.ownerLevelsUp || 1
              ).key
            )
          : this.aboutValue.property;
      let valuePayload = {};
      if (value.raw) {
        valuePayload[dev.InternalKeys.raw] = value.raw;
      }
      if (value.payload) {
        valuePayload[dev.InternalKeys.payload] = value.payload;
      }
      representation[dev.InternalKeys.value] = valuePayload;
      return representation;
    }
    return null;
  }

  apply(snapshot) {
    if (snapshot.exists() && snapshot.hasChild("t_pth")) {
      const snapVal = snapshot.val();
      const valueDescriptor = snapVal[dev.InternalKeys.value] || {};
      const raw = valueDescriptor[dev.InternalKeys.raw];
      const payload = valueDescriptor[dev.InternalKeys.payload];
      const src = snapVal.t_pth;
      const v = new this.aboutValue.class.prototype.constructor(
        snapshot.ref.root.child(src),
        { raw: raw, payload: payload }
      );
      this.value = v;
      return v;
    } else {
      this.value = null;
      return null;
    }
  }
}

class File extends Property {
  constructor(ref, options) {
    super(ref, options);
    Object.defineProperty(this, "metadata", {
      value: options.metadata,
      writable: false,
      enumerable: false,
      configurable: true
    });
    Object.defineProperty(this, "$_url", {
      writable: true,
      enumerable: false,
      configurable: true
    });
  }

  get url() {
    return this.$_url;
  }

  updater(transaction) {
    return new Proxy(this, new RealtimeFileUpdater(transaction));
  }

  encode(value) {
    return value ? { file: value, metadata: this.metadata } : null;
  }

  _write(value, transaction) {
    transaction.addFile(this.path, value);
  }

  getUrl(storage) {
    const self = this;
    return storage
      .ref(this.path)
      .getDownloadURL()
      .then(url => {
        self.$_url = url;
        return url;
      })
      .catch(e => {
        if (e.code == "storage/object-not-found") {
          console.log(e.message);
          self.$_url = null;
        } else {
          console.error("File URL cannot be get", e);
        }
      });
  }
}
File.prototype.getUrlIfUndefined = function(storage) {
  if (this.$_url === undefined) {
    return this.getUrl(storage);
  }
  return Promise.resolve(this.$_url);
};
File.prototype.getUrlIfEmpty = function(storage) {
  if (!this.$_url) {
    return this.getUrl(storage);
  }
  return Promise.resolve(this.$_url);
};
File.png = function(ref, options) {
  options.metadata = { contentType: "image/png" };
  return new File(ref, options);
};
File.jpeg = function(ref, options) {
  options.metadata = { contentType: "image/jpeg" };
  return new File(ref, options);
};
exports.File = File;

// Object

exports.RealtimeObject = class RealtimeObject extends RealtimeValue {
  get excludedKeys() {
    return [];
  }

  runObserving() {
    return this._observe(dev.DataEvents.value);
  }

  stopObserving() {
    return this._stopObserving(dev.DataEvents.value);
  }

  get isObserved() {
    return this._isObserved(dev.DataEvents.value);
  }

  updater(transaction) {
    return new Proxy(this, new ObjectUpdaterHandler(transaction));
  }

  willRemove(transaction, ancestor) {
    super.willRemove(transaction, ancestor);
    this._enumerateProps((prop, key) => {
      if (prop instanceof RealtimeValue) {
        prop.willRemove(transaction, ancestor);
      }
    });
    let linksWillNotBeRemovedInAncestor = this.ref.parent.isEqual(ancestor);
    let linksProp = new Property(
      linksRef(this.ref.child(dev.InternalKeys.linkItems))
    );
    transaction.addPrecondition(transaction => {
      return linksProp.load().then(links => {
        Object.keys(links || {})
          .flatMap(linkKey => links[linkKey])
          .forEach(link => {
            if (!dev.Utilities.pathHasAncestor(link, ancestor)) {
              transaction.addValue(link, null);
            }
          });
        if (linksWillNotBeRemovedInAncestor) {
          transaction.addValue(dev.Utilities.rootPath(linksProp.ref), null);
        }
      });
    });
  }

  write(transaction) {
    super.write(transaction);
    this._writeSystemValues(transaction);
    this._enumerateProps((prop, label) => {
      if (!this.conditionForWrite(prop, label)) return;
      if (prop instanceof RealtimeValue) {
        prop.write(transaction);
      } else if (prop !== undefined) {
        transaction.addValue(dev.Utilities.rootPath(this.ref.child(label)), prop);
      }
    });
  }

  conditionForWrite(prop, label) {
    return true;
  }
  conditionForRead(prop, label, snapshot) {
    return true;
  }

  apply(snapshot) {
    this._apply(snapshot);
    return super.apply(snapshot);
  }

  _apply(snapshot) {
    this._enumerateProps((prop, label) => {
      if (!this.conditionForRead(prop, label, snapshot)) return;
      if (prop instanceof RealtimeValue) {
        prop.apply(snapshot.child(prop.key));
      } else {
        this.applyDataForExplicitProperty(label, snapshot);
      }
    });
  }

  applyDataForExplicitProperty(label, parentSnapshot) {
    if (parentSnapshot.hasChild(label)) {
      this[label] = parentSnapshot.child(label).val();
    } else {
      this[label] = undefined;
    }
  }

  _enumerateProps(loop) {
    Object.keys(this).forEach(label => {
      if (this.excludedKeys.includes(label) || label.startsWith("$_")) return;
      loop(this[label], label);
    });
  }

  toJSON() {
    let json = {};
    Object.keys(this).forEach(key => {
      if (this.excludedKeys.includes(key)) return;
      const prop = this[key];
      if (prop instanceof RealtimeValue) {
        json[prop.key] = prop.toJSON();
      } else {
        json[key] = prop;
      }
    });
    return json;
  }
}

// Collections

class RealtimeCollection extends RealtimeValue {
  constructor(ref, ascending = true) {
    super(ref);
    this.elements = [];
    this.ascending = ascending; // true - default behavior of firebase
  }

  runObserving() {
    return this._observe(dev.DataEvents.value);
  }
  stopObserving() {
    return this._stopObserving(dev.DataEvents.value);
  }
  get isObserved() {
    return this._isObserved(dev.DataEvents.value);
  }

  [Symbol.iterator]() {
    let index = 0;
    return {
      next: () => {
        if (index < this.elements.length) {
          return { value: this.elements[index++], done: false };
        } else {
          index = 0; //If we would like to iterate over this again without forcing manual update of the index
          return { done: true };
        }
      }
    };
  }

  get length() {
    return this.elements.length;
  }

  get first() {
    return this.length ? this.elements[0] : null;
  }

  elementAt(index) {
    return this.elements[index];
  }

  apply(snapshot) {
    super.apply(snapshot);
    let elements = [];
    snapshot.forEach(child => {
      elements.push(this._elementFrom(child));
    });
    if (!this.ascending) {
      elements = elements.reverse();
    }
    this.elements = elements;
    return elements;
  }
  _elementFrom(snapshot) {
    return snapshot.val();
  }

  updater(transaction) {
    return new Proxy(this, new RealtimeCollectionUpdater(transaction));
  }

  forEach(callback) {
    this.elements.forEach(callback);
  }
  map(transform) {
    return this.elements.map(transform);
  }
  flatMap(transform) {
    return this.elements.flatMap(transform);
  }
  reduce(reducer, initial) {
    return this.elements.reduce(reducer, initial);
  }
  filter(predicate) {
    return this.elements.filter(predicate);
  }
  find(predicate) {
    return this.elements.find(predicate);
  }
  sorted(descriptor) {
    const copy = this.elements.slice();
    return copy.sort(descriptor);
  }

  toJSON() {
    return this.elements.map(el => {
      if (el instanceof RealtimeValue) {
        return el.toJSON();
      } else {
        return el;
      }
    });
  }
}

exports.Values = class Values extends RealtimeCollection {
  constructor(ref, { elementClass, ascending, viewWritable }) {
    super(ref, ascending);
    Object.defineProperty(this, "elementClass", {
      value: elementClass,
      writable: false,
      enumerable: false,
      configurable: true
    });
    Object.defineProperty(this, "viewWritable", {
      value: viewWritable,
      writable: false,
      enumerable: false,
      configurable: true
    });
    this._view = null;
  }

  get view() {
    if (this._view) return this._view;
    this._view = new CollectionView(
      linksRef(this.ref).child(dev.InternalKeys.items),
      this.ascending
    );
    viewedCollections.set(this._view, this);
    return this._view;
  }

  load(throughView) {
    if (throughView) {
      return this.view.load().then(() => this.elements);
    } else {
      return super.load();
    }
  }

  _viewDidChange(viewElements) {
    this.elements = viewElements.map(item => {
      let options = {};
      if (item[1][dev.InternalKeys.value]) {
        options.raw = item[1][dev.InternalKeys.value][dev.InternalKeys.raw];
        options.payload = item[1][dev.InternalKeys.value][dev.InternalKeys.payload];
      }
      return new this.elementClass.prototype.constructor(
        this.ref.child(item[0]),
        options
      );
    });
    return this.elements;
  }

  updater(transaction) {
    const finder = element => el => el.key == element.key;
    return new Proxy(
      this,
      new RepresentableCollectionMutator(
        transaction,
        this,
        finder,
        this.elements.slice()
      )
    );
  }

  write(transaction) {
    if (this._view) {
      this._view.write(transaction);
    }
    this.elements.forEach(element => {
      this.writeElement(element, transaction);
    });
  }

  writeElement(element, transaction) {
    debug(() => {
      if (!(element instanceof this.elementClass)) {
        console.error("Tries write element with unexpected type", element);
        throw Error("Tries write element with unexpected type");
      }
    });
    if (!element.ref.parent.isEqual(this.ref)) {
      throw Error("Tries write element that referenced to external space");
    }
    element.write(transaction);
    if (this.viewWritable) {
      const linkKey = this.view.ref.push().key;
      let viewElement = {};
      viewElement[dev.InternalKeys.link] = linkKey;
      let valuePayload = {};
      if (element.raw) {
        valuePayload[dev.InternalKeys.raw] = element.raw;
      }
      if (element.payload) {
        valuePayload[dev.InternalKeys.payload] = element.payload;
      }
      viewElement[dev.InternalKeys.value] = valuePayload;
      const viewElementPath = dev.Utilities.rootPath(
        this.view.ref.child(element.key)
      );
      transaction.addValue(viewElementPath, viewElement);

      // element link
      const links = [viewElementPath];
      transaction.addValue(
        dev.Utilities.rootPath(
          linksRef(element.ref)
            .child(dev.InternalKeys.linkItems)
            .child(linkKey)
        ),
        links
      );
    }
  }

  removeElement(element, transaction) {
    element.remove(transaction);
    if (this.viewWritable) {
      transaction.addValue(
        dev.Utilities.rootPath(this.view.ref.child(element.key)),
        null
      );
      // transaction.addValue(dev.Utilities.rootPath(
      //   linksRef(element.ref)
      //     .child(dev.InternalKeys.linkItems)
      //     .child(linkKey)
      // ), null);
    }
  }

  _elementFrom(snapshot) {
    return this.elementClass.fromSnapshot(snapshot);
  }
}

exports.AssociatedValues = class AssociatedValues extends RealtimeCollection {
  constructor(
    ref,
    { keyObject, valueClass, ascending, viewWritable, shouldLinking }
  ) {
    if (viewWritable && !(valueClass.prototype instanceof RealtimeValue)) {
      throw Error("Collection view sync is supported only for Realtime values");
    }
    super(ref, ascending);
    Object.defineProperty(this, "keyObject", {
      value: keyObject,
      writable: false,
      enumerable: false,
      configurable: true
    });
    Object.defineProperty(this, "valueClass", {
      value: valueClass,
      writable: false,
      enumerable: false,
      configurable: true
    });
    Object.defineProperty(this, "viewWritable", {
      value: viewWritable,
      writable: false,
      enumerable: false,
      configurable: true
    });
    Object.defineProperty(this, "shouldLinking", {
      value: shouldLinking,
      writable: false,
      enumerable: false,
      configurable: true
    });
    this._view = null;
  }

  get view() {
    if (this._view) return this._view;
    this._view = new CollectionView(
      linksRef(this.ref).child(dev.InternalKeys.items),
      this.ascending
    );
    viewedCollections.set(this._view, this);
    return this._view;
  }

  load(throughView) {
    if (throughView) {
      return this.view.load().then(() => this.elements);
    } else {
      return super.load();
    }
  }

  _viewDidChange(viewElements) {
    this.elements = viewElements.map(item => {
      let valueOptions = {};
      if (item[1][dev.InternalKeys.value]) {
        valueOptions.raw = item[1][dev.InternalKeys.value][dev.InternalKeys.raw];
        valueOptions.payload =
          item[1][dev.InternalKeys.value][dev.InternalKeys.payload];
      }
      let keyOptions = {};
      if (item[1][dev.InternalKeys.key]) {
        keyOptions.raw = item[1][dev.InternalKeys.key][dev.InternalKeys.raw];
        keyOptions.payload = item[1][dev.InternalKeys.key][dev.InternalKeys.payload];
      }
      return [
        new this.keyObject.class.prototype.constructor(
          this.ref.root.child(this.keyObject.path + "/" + item[0]),
          keyOptions
        ),
        new this.valueClass.prototype.constructor(
          this.ref.child(item[0]),
          valueOptions
        )
      ];
    });
    return this.elements;
  }

  updater(transaction) {
    const finder = element => el => el[0].key == element[0].key;
    return new Proxy(
      this,
      new RepresentableCollectionMutator(
        transaction,
        this,
        finder,
        this.elements.slice()
      )
    );
  }

  write(transaction) {
    if (this._view) {
      this._view.write(transaction);
    }
    this.elements.forEach(element => {
      this.writeElement(element, transaction);
    });
  }

  writeElement(element, transaction) {
    debug(() => {
      if (!(element[1] instanceof this.valueClass)) {
        console.error("Tries write element with unexpected type", element);
        throw Error("Tries write element with unexpected type");
      }
    });
    const isRealtimeValue = element[1] instanceof RealtimeValue;
    if (isRealtimeValue) {
      if (!element[1].ref.parent.isEqual(this.ref)) {
        throw Error("Tries write element that referenced to external space");
      }
      if (element[1].key != element[0].key) {
        throw Error(
          "Tries write value that referenced to different key with key object"
        );
      }
      element[1].write(transaction);
    } else {
      transaction.addValue(
        dev.Utilities.rootPath(this.ref.child(element[0].key)),
        element[1]
      );
    }
    if (this.viewWritable && isRealtimeValue) {
      const linkKey = this.view.ref.push().key;
      let viewElement = {};
      viewElement[dev.InternalKeys.link] = linkKey;
      let keyPayload = {};
      if (element[0].raw) {
        keyPayload[dev.InternalKeys.raw] = element[0].raw;
      }
      if (element[0].payload) {
        keyPayload[dev.InternalKeys.payload] = element[0].payload;
      }
      viewElement[dev.InternalKeys.key] = keyPayload;
      let valuePayload = {};
      if (element[1].raw) {
        valuePayload[dev.InternalKeys.raw] = element[1].raw;
      }
      if (element[1].payload) {
        valuePayload[dev.InternalKeys.payload] = element[1].payload;
      }
      viewElement[dev.InternalKeys.value] = valuePayload;
      const viewElementPath = dev.Utilities.rootPath(
        this.view.ref.child(element[1].key)
      );
      transaction.addValue(viewElementPath, viewElement);

      // element link
      const valueLinksPath = dev.Utilities.rootPath(
        linksRef(element[1].ref)
          .child(dev.InternalKeys.linkItems)
          .child(linkKey)
      );
      if (this.shouldLinking) {
        const keyLinksPath = dev.Utilities.rootPath(
          linksRef(element[0].ref)
            .child(dev.InternalKeys.linkItems)
            .child(linkKey)
        );
        let links = [];
        links.push(dev.Utilities.rootPath(element[1].ref));
        links.push(dev.Utilities.rootPath(linksRef(element[1].ref)));
        links.push(viewElementPath);
        transaction.addValue(keyLinksPath, links);
        transaction.addValue(valueLinksPath, [viewElementPath, keyLinksPath]);
      } else {
        transaction.addValue(valueLinksPath, [viewElementPath]);
      }
    }
  }

  removeElement(element, transaction) {
    const isRealtimeValue = element[1] instanceof RealtimeValue;
    if (isRealtimeValue) {
      element[1].remove(transaction);
    } else {
      transaction.addValue(
        dev.Utilities.rootPath(this.ref.child(element[0].key)),
        null
      );
    }
    if (this.viewWritable && isRealtimeValue) {
      const viewElementPath = dev.Utilities.rootPath(
        this.view.ref.child(element[1].key)
      );
      transaction.addValue(viewElementPath, null);

      // element link
      if (this.shouldLinking) {
        const self = this;
        transaction.addPrecondition(transaction => {
          self.view.valueFor(element[0].key).then(viewElement => {
            if (!viewElement) {
              throw Error("Element has no reference in view collection");
            }
            const keyLinksPath = dev.Utilities.rootPath(
              linksRef(element[0].ref)
                .child(dev.InternalKeys.linkItems)
                .child(viewElement[1][dev.InternalKeys.link])
            );
            transaction.addValue(keyLinksPath, null);
          });
        });
      }
      // const valueLinksPath = dev.Utilities.rootPath(
      //   linksRef(element[1].ref).child(dev.InternalKeys.linkItems)
      // );
      // transaction.addValue(valueLinksPath, null);
    }
  }

  _elementFrom(snapshot) {
    return [
      new this.keyObject.class.prototype.constructor(
        snapshot.ref.root.child(this.keyObject.path + "/" + snapshot.key) // TODO: options
      ),
      this.valueClass.fromSnapshot(snapshot)
    ];
  }

  existedValueFor(key) {
    const item = this.elements.find(val => val[0].key == key.key);
    if (item) return item[1];
    else return null;
  }

  valueFor(key) {
    const existed = this.existedValueFor(key);
    if (existed) return Promise.resolve(existed);
    return this.ref
      .orderByKey()
      .equalTo(key.key)
      .once("value")
      .then(this.apply.bind(this)) // TODO: Will overwrite other elements
      .then(() => this.valueFor(key));
  }
}

class Relations extends RealtimeCollection {
  constructor(ref, { element, ascending }) {
    super(ref, ascending);
    Object.defineProperty(this, "aboutElement", {
      value: element,
      writable: false,
      enumerable: false,
      configurable: true
    });
  }

  updater(transaction) {
    const finder = element => el => el.key == element.key;
    return new Proxy(
      this,
      new RepresentableCollectionMutator(
        transaction,
        this,
        finder,
        this.elements.slice()
      )
    );
  }

  write(transaction) {
    this.elements.forEach(element => {
      this.writeElement(element, transaction);
    });
  }

  writeElement(element, transaction) {
    let representation = {};
    representation[dev.InternalKeys.targetPath] = this.aboutElement.path
      ? dev.Utilities.dbPath(
          this.ref.root.child(this.aboutElement.path),
          element.ref
        )
      : element.path;
    representation[dev.InternalKeys.relatedProperty] =
      typeof this.aboutElement.property == "function"
        ? this.aboutElement.property(
            dev.Utilities.ancestorOnLevelUp(
              this.ref,
              this.aboutElement.ownerLevelsUp || 1
            ).key
          )
        : this.aboutElement.property;
    let valuePayload = {};
    if (element.raw) {
      valuePayload[dev.InternalKeys.raw] = element.raw;
    }
    if (element.payload) {
      valuePayload[dev.InternalKeys.payload] = element.payload;
    }
    representation[dev.InternalKeys.value] = valuePayload;
    transaction.addValue(
      dev.Utilities.rootPath(this.ref.child(element.key)),
      representation
    );
  }

  removeElement(element, transaction) {
    transaction.addValue(dev.Utilities.rootPath(this.ref.child(element.key)), null);
  }

  _elementFrom(snapshot) {
    const relation = snapshot.val();
    let valueOptions = {};
    if (relation[dev.InternalKeys.value]) {
      valueOptions.raw = relation[dev.InternalKeys.value][dev.InternalKeys.raw];
      valueOptions.payload = relation[dev.InternalKeys.value][dev.InternalKeys.payload];
    }
    return new this.aboutElement.class.prototype.constructor(
      this.ref.root.child(relation.t_pth),
      valueOptions
    );
  }
}
Relations.prototype.containsWithKey = function(key) {
  if (this.isObserved) {
    return Promise.resolve(
      this.elements.findIndex(val => val.key == key) != -1
    );
  }
  return this.ref
    .orderByKey()
    .equalTo(key)
    .once("value")
    .then(snap => snap.exists());
};
exports.Relations = Relations;

var viewedCollections = new WeakMap();
class CollectionView extends RealtimeCollection {
  constructor(ref, ascending) {
    super(ref, ascending);
    Object.defineProperty(this, "elements", {
      set(newValue) {
        const ownerCollection = viewedCollections.get(this);
        if (ownerCollection) {
          ownerCollection._viewDidChange(newValue);
        }
      }
    });
  }

  _elementFrom(snapshot) {
    return [snapshot.key, snapshot.val()];
  }

  existedValueFor(key) {
    const item = this.elements.find(val => val[0] == key);
    if (item) return item[1];
    else return null;
  }

  valueFor(key) {
    const existed = this.existedValueFor(key);
    if (existed) return existed;
    return this.ref
      .orderByKey()
      .equalTo(key)
      .once("value")
      .then(s => [s.key, s.val()]);
  }
}

exports.PagingDataExplorer = class PagingDataExplorer {
  constructor(ref, pageSize, ascending) {
    this.ref = ref;
    this.pageSize = pageSize;
    this.ascending = ascending;
  }

  next(lastKey) {
    return this._observe(dev.DataEvents.value, this.ascending ? null : lastKey, this.ascending ? lastKey : null, this.ascending, this.pageSize);
  }

  previuos(firstKey) {
    return this._observe(dev.DataEvents.value, this.ascending ? firstKey : null, this.ascending ? null : firstKey, this.ascending, this.pageSize);
  }

  _observe(event, before, after, ascending, limit) {
    let query = this.ref.orderByKey();
    if (before) {
        query = query.endAt(before);
        limit += 1;
    }
    if (after) {
        query = query.startAt(after);
        limit += 1;
    }
    query = ascending ? query.limitToFirst(limit) : query.limitToLast(limit);

    return query.once(event);
  }
}

class Transaction {
  constructor(database, storage) {
    this.database = database;
    this.storage = storage;
    this.values = {};
    this.files = {};
    this.preconditions = [];
  }

  toString() {
    return `values: ${this.values.toString()},\nfiles: ${this.files.toString()}`;
  }
  toJSON() {
    return {
      values: this.values,
      files: this.files
    };
  }

  addValue(key, value) {
    if (value === undefined) {
      debug(() => {
        throw Error("Transaction must not receive undefined values");
      });
      value = null;
    }
    if (typeof value === "object" && value) {
      value = JSON.parse(JSON.stringify(value));
      debug(() => {
        console.log("Transaction: new value was copy", value);
      });
    }
    debug(() => {
      if (this.values[key]) {
        console.warn(
          "Transaction: overwrite value ",
          this.values[key],
          "in key: ",
          key,
          "with value",
          value
        );
      }
      const ancestorKey = Object.keys(this.values).find(k => key.startsWith(k));
      if (ancestorKey) { // TODO: Resolve this vulnerability
        console.warn(
          "Transaction: already has value ",
          { [ancestorKey]: this.values[ancestorKey] },
          "Tries to add value: ",
          { [key]: value }
        );
      }
    });
    this.values[key] = value;
  }
  addFile(key, file) {
    debug(() => {
      if (this.files[key]) {
        console.warn(
          "Overwrite file ",
          this.files[key],
          "in key: ",
          key,
          "with file",
          file
        );
      }
    });
    this.files[key] = file;
  }

  addPrecondition(precondition) {
    this.preconditions.push(precondition);
  }

  _getValue(key) {
    return this.values[key];
  }

  _runPreconditions() {
    const preconds = this.preconditions.slice();
    this.preconditions = [];
    return Promise.all(preconds.map(p => p(this))).then(() => {
      if (this.preconditions.length) {
        return this._runPreconditions();
      }
    });
  }

  commit(concurrency) {
    return this._runPreconditions().then(() => {
      const filesPromise = () =>
        Promise.allSettled(
          Object.entries(this.files).map(entry => {
            const ref = this.storage.ref(entry[0]);
            return entry[1]
              ? ref.put(entry[1].file, entry[1].metadata)
              : ref.delete().then(
                  v => v,
                  e => {
                    if (e.code == "storage/object-not-found") return true;
                    throw e;
                  }
                );
          })
        );
      if (concurrency) {
        return Promise.all([
          filesPromise(),
          this.database.ref().update(this.values)
        ]);
      } else {
        return this.database
          .ref()
          .update(this.values)
          .then(filesPromise);
      }
    });
  }
}
exports.Transaction = Transaction;

class ObjectUpdaterHandler {
  constructor(transaction) {
    this.transaction = transaction;
  }

  toJSON() {
    return Object.entries(this).reduce((res, entry) => {
      if (entry[1] instanceof RealtimeValue) {
        const json = entry[1].toJSON();
        if (json !== undefined) {
          res[entry[0]] = json;
        }
      }
      return res;
    }, {});
  }

  commit(concurrency) {
    const trans = this.transaction;
    this.writeChanges(trans);
    return trans.commit(concurrency);
  }

  writeChanges(transaction) {
    Object.entries(this).forEach(entry => {
      if (entry[1] instanceof RealtimeValue) {
        entry[1].writeChanges(transaction);
      }
      // TODO: raw properties
    });
  }

  get(target, property, receiver) {
    const definedProp = Reflect.get(this, property);
    if (definedProp !== undefined) {
      return typeof definedProp == "function"
        ? definedProp.bind(this)
        : definedProp;
    }
    if (property == "__ob__") {
      return undefined;
    }
    const propValue = Reflect.get(target, property);
    if (propValue instanceof RealtimeValue) {
      const proxy = propValue.updater(this.transaction);
      reactivityEnvironment.set(this, property, proxy);
      return proxy;
    } else {
      return typeof propValue == "function"
        ? propValue.bind(target)
        : propValue;
    }
  }

  set(target, property, value, receiver) {
    return false;
  }

  defineProperty(target, key, descriptor) {
    const result = Reflect.defineProperty(this, key, descriptor);
    return result;
  }

  getOwnPropertyDescriptor(target, prop) {
    const descr = Reflect.getOwnPropertyDescriptor(this, prop);
    return descr;
  }

  has(target, key) {
    return key in this;
  }
}

class PropertyUpdaterHandler {
  constructor() {
    this.encoded = undefined;
    this.value = undefined;
  }

  toJSON() {
    return this.encoded ? this.encoded.value : undefined;
  }

  writeChanges(transaction) {
    if (this.encoded) {
      this.___add(transaction, this.encoded);
    }
  }

  ___add(transaction, encoded) {
    transaction.addValue(encoded.path, encoded.value);
  }

  get(target, property, receiver) {
    const definedProp = Reflect.get(this, property);
    if (definedProp !== undefined) {
      return typeof definedProp == "function"
        ? definedProp.bind(this)
        : definedProp;
    }
    if (property == "__ob__") {
      return undefined;
    }
    const propValue = Reflect.get(target, property);
    return typeof propValue == "function" ? propValue.bind(target) : propValue;
  }

  set(target, property, newValue, receiver) {
    if (property in this) {
      const result = Reflect.set(this, property, newValue);
      if (property === "value") {
        this.encoded = { path: target.path, value: target.encode(newValue) };
      }
      return result;
    }
    return false;
  }

  defineProperty(target, key, descriptor) {
    return Reflect.defineProperty(this, key, descriptor);
  }

  getOwnPropertyDescriptor(target, prop) {
    const descr = Reflect.getOwnPropertyDescriptor(this, prop);
    return descr;
  }

  has(target, key) {
    return key in this;
  }
}

class RealtimeFileUpdater extends PropertyUpdaterHandler {
  ___add(transaction, encoded) {
    transaction.addFile(encoded.path, encoded.value);
  }
}

class RealtimeCollectionUpdater {
  constructor(transaction) {
    this.transaction = transaction;
  }

  toJSON() {
    return [];
  }
}

class RepresentableCollectionMutator {
  constructor(transaction, target, finder, elements = []) {
    this.transaction = transaction;
    this.target = target;
    this.finder = finder;
    this.elements = elements; // TODO: Probably it does not need
    this.changes = { added: [], removed: [] };
  }

  get length() {
    return this.elements.length;
  }

  commit(concurrency) {
    const trans = this.transaction;
    this.writeChanges(trans);
    return trans.commit(concurrency);
  }

  writeChanges(transaction) {
    this.changes.added.forEach(el => {
      this.target.writeElement(el, transaction);
    });
    this.changes.removed.forEach(el => {
      this.target.removeElement(el, transaction);
    });
  }

  push(element) {
    const find = this.finder(element);
    debug(() => {
      if (this.changes.added.find(find) || this.elements.find(find)) {
        console.warn(
          "Tries push element that already exists",
          this.elements,
          element
        );
      }
    });
    this.changes.added.push(element);
    this.elements.push(element);

    const removedIndex = this.changes.removed.findIndex(find);
    if (removedIndex != -1) {
      this.changes.removed.splice(removedIndex, 1);
    }
  }

  remove(element) {
    const find = this.finder(element);
    const addedIndex = this.changes.added.findIndex(find);
    if (addedIndex != -1) {
      this.changes.added.splice(addedIndex, 1);
    } else {
      this.changes.removed.push(element);
    }
    const elementsIndex = this.elements.findIndex(find);
    if (elementsIndex != -1) {
      this.elements.splice(elementsIndex, 1);
    } else {
      debug(() => {
        console.warn(
          "Tries remove element that does not exist",
          this.elements,
          element
        );
        // throw Error("Tries remove element that does not exist");
      });
    }
  }

  get(target, property, receiver) {
    const definedProp = Reflect.get(this, property);
    if (definedProp !== undefined) {
      return typeof definedProp == "function"
        ? definedProp.bind(this)
        : definedProp;
    }
    if (property == "__ob__") {
      return undefined;
    }
    const propValue = Reflect.get(target, property);
    return typeof propValue == "function" ? propValue.bind(target) : propValue;
  }
}