//
//  UIKit.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 29/09/2017.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import UIKit

// MARK: UITableView - Adapter

internal class _TableViewSectionedAdapter: NSObject, UITableViewDataSource, UITableViewDelegate, UITableViewDataSourcePrefetching {
    internal func numberOfSections(in tableView: UITableView) -> Int {
        fatalError("Need override this method")
    }

    internal func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fatalError("Need override this method")
    }

    internal func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        fatalError("Need override this method")
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { return 0.0 }
    @available(iOS 2.0, *)
    internal func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {}

    @available(iOS 6.0, *)
    internal func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {}
    internal func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {}

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {}
    func tableView(_ tableView: UITableView, didEndDisplayingHeaderView view: UIView, forSection section: Int) {}
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? { return nil }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { return nil }
    func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int { return index }
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { return 0.0 }
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {}
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle { return .delete }
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {}
//    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {}

    // UIScrollView

    func scrollViewDidScroll(_ scrollView: UIScrollView) {}
    func scrollViewDidZoom(_ scrollView: UIScrollView) {}
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {}
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {}
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {}
    func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {}
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {}
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {}
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { return nil }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {}
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {}
    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool { return true }
    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {}
    @available(iOS 11.0, *)
    func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {}
}

struct TypeKey: Hashable {
    fileprivate let type: AnyClass

    var hashValue: Int {
        return ObjectIdentifier(type).hashValue
    }

    static func ==(lhs: TypeKey, rhs: TypeKey) -> Bool {
        return lhs.type === rhs.type
    }

    static func `for`<T: AnyObject>(_ type: T.Type) -> TypeKey {
        return TypeKey(type: type)
    }
}
extension UITableViewCell {
    // convenience static computed property to get the wrapped metatype value.
    static var typeKey: TypeKey {
        return TypeKey.for(self)
    }
    var typeKey: TypeKey {
        return type(of: self).typeKey
    }
}

extension SignedInteger {
    func toOther<SI: SignedInteger>() -> SI {
        return SI(self)
    }
}
