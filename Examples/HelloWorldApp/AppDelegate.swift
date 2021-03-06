//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet var outlineView: ExtOutlineView!
    @IBOutlet var empNameLabel: Label!
    @IBOutlet var empDeptLabel: Label!
    
    private var nsUndoManager: SPUndoManager!
    private var model: ViewModel!
    private var listView: ListView<RowArrayElement>!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.delegate = self
        
        // Prepare the undo manager
        nsUndoManager = SPUndoManager()
        let undoManager = PLBindableControls.UndoManager(nsmanager: nsUndoManager)
        
        // Bind the views to the view model
        model = ViewModel(undoManager: undoManager)
        listView = ListView(model: model.employeesListModel, outlineView: outlineView)
        listView.selection <~> model.employeesListSelection
        empNameLabel.string <~ model.selectedEmployeeName
        empDeptLabel.string <~ model.selectedEmployeeDepartment
    }
    
    func windowWillReturnUndoManager(_ window: NSWindow) -> Foundation.UndoManager? {
        return nsUndoManager
    }
}
