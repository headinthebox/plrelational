//
//  DocOutlineView.swift
//  Relational
//
//  Created by Chris Campbell on 5/5/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import libRelational

// Note: Normally this would be an NSView subclass, but for the sake of expedience we defined the UI in
// a single Document.xib, so this class simply manages a subset of views defined in that xib.
class DocOutlineView {
    
    private let treeView: TreeView<Row>
    
    init(model: TreeViewModel<Row>, outlineView: NSOutlineView) {
        self.treeView = TreeView(model: model, outlineView: outlineView)
        self.treeView.animateChanges = true
    }
}
