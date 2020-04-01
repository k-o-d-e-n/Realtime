'use strict';

exports.InternalKeys = Object.freeze({
    /// version of RealtimeValue
    modelVersion: "__mv",
    /// root database key for links hierarchy
    links: "__lnks",
    /// key of RealtimeValue in 'links' branch which stores all external links to this values
    linkItems: "__l_itms",
    /// key of RealtimeCollection in 'links' branch which stores prototypes of all collection elements
    items: "__itms",
    /// key of collection element prototype which indicates priority
    index: "__i",
    /// key to store user payload data
    payload: "__pl",
    /// key of associated collection element prototype
    key: "__key",
    /// key of associated collection element prototype
    value: "__val",
    /// ket of collection element prototype to store link key
    link: "__lnk",
    /// Indicates raw value of enum, or subclass
    raw: "__raw",
    /// key of reference to source location
    source: "__src",
    targetPath: "t_pth",
    relatedProperty: "r_prop"
  });
  
  exports.DataEvents = Object.freeze({
    value: "value",
    childAdded: "child_added",
    childRemoved: "child_removed",
    childChanged: "child_changed",
    childMoved: "child_moved"
  });

  exports.Utilities = class Utilities {
    static dbPath(fromRef, toRef) {
      const toPath = toRef.toString();
      const fromPath = fromRef.toString();
      if (!toPath.startsWith(fromPath)) {
        debug(() => {
          console.error(
            "Cannot get relative path, because references locate in different branches:",
            fromPath,
            toPath
          );
        });
        throw Error(
          "Cannot get relative path, because references locate in different branches"
        );
      }
      return toPath.slice(
        fromPath.length + (fromRef.isEqual(fromRef.root) ? 0 : 1)
      );
    }
    static rootPath(toRef) {
      return this.dbPath(toRef.root, toRef);
    }
    static refThatHasParentWith(key, ref, sliced) {
      let parts = Utilities.rootPath(ref)
        .split("/")
        .slice(sliced);
      while (parts.length > 1 && parts[parts.length - 2] != key) {
        parts.pop();
      }
  
      if (parts.length == 1) return null;
      return ref.root.child(parts.join("/"));
    }
    static ancestorOnLevelUp(ref, levelsUp) {
      while (levelsUp != 0 && ref.parent) {
        ref = ref.parent;
        levelsUp -= 1;
      }
      return ref;
    }
    static hasAncestor(ref, ancestor) {
      return this.pathHasAncestor(ref.toString(), ancestor);
    }
    static pathHasAncestor(toPath, ancestor) {
      const fromPath = ancestor.toString();
      return toPath.startsWith(fromPath);
    }
  }