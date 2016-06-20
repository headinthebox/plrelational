//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class PopUpButton<T: Equatable>: NSPopUpButton {

    public lazy var items: Property<[MenuItem<T>]> = Property { [unowned self] value, _ in
        // Clear the menu
        self.removeAllItems()

        // Add the menu items
        self.nativeMenuItems = value.map{ NativeMenuItem(model: $0) }
        for item in self.nativeMenuItems! {
            self.menu?.addItem(item.nsitem)
        }

        // Insert the default menu item, if we have one
        if let defaultMenuItem = self.defaultMenuItem {
            self.menu?.insertItem(defaultMenuItem.nsitem, atIndex: 0)
        }
        
        // Set the selected item
        self.setSelectedItem(self.selectedObject.get())
    }

    private lazy var _selectedObject: ValueBidiProperty<T?> = ValueBidiProperty(
        initialValue: nil,
        didSet: { [unowned self] value, _ in
            self.setSelectedItem(value)
        }
    )
    public var selectedObject: BidiProperty<T?> { return _selectedObject }

    public var defaultItemContent: MenuItemContent<T>? {
        didSet {
            if let existingItem = defaultMenuItem?.nsitem {
                existingItem.menu?.removeItem(existingItem)
            }
            if let content = defaultItemContent {
                let model = MenuItem(.Normal(content))
                let nativeItem = NativeMenuItem(model: model)
                nativeItem.nsitem.hidden = true
                nativeItem.nsitem.enabled = false
                defaultMenuItem = nativeItem
                menu?.insertItem(nativeItem.nsitem, atIndex: 0)
            } else {
                defaultMenuItem = nil
            }
        }
    }

    // TODO: We hang on to these just to maintain strong references while their underlying
    // NSMenuItems are attached to the NSMenu
    private var nativeMenuItems: [NativeMenuItem<T>]?
    private var defaultMenuItem: NativeMenuItem<T>?
    
    private var selfInitiatedSelectionChange = false
    private var selectedIndex = -1

    public override init(frame: NSRect, pullsDown flag: Bool) {
        super.init(frame: frame, pullsDown: flag)
        
        autoenablesItems = false
        target = self
        action = #selector(selectionChanged(_:))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("NSCoding not supported")
    }
    
    private func setSelectedItem(object: T?) {
        selfInitiatedSelectionChange = true
        if let object = object, menu = menu {
            // Find menu item that matches given object
            let index = menu.itemArray.indexOf({
                let nativeItem = $0.representedObject as? NativeMenuItem<T>
                return nativeItem?.object == object
            })
            if let index = index {
                selectItemAtIndex(index)
                selectedIndex = index
            } else {
                selectItem(defaultMenuItem?.nsitem)
                selectedIndex = -1
            }
        } else {
            // Select the default item if one exists, otherwise clear selection
            selectItem(defaultMenuItem?.nsitem)
            selectedIndex = -1
        }
        selfInitiatedSelectionChange = false
    }
    
    @objc func selectionChanged(sender: NSPopUpButton) {
        if selfInitiatedSelectionChange { return }
        
        guard let selectedItem = sender.selectedItem else { return }
        guard let nativeItem = selectedItem.representedObject as? NativeMenuItem<T> else { return }
        
        switch nativeItem.model.type {
        case .Normal:
            guard let object = nativeItem.object else { return }
            selfInitiatedSelectionChange = true
            _selectedObject.change(newValue: object, transient: false)
            selfInitiatedSelectionChange = false
            
        case .Momentary(_, let action):
            selfInitiatedSelectionChange = true
            if selectedIndex >= 0 {
                selectItemAtIndex(selectedIndex)
            } else {
                selectItem(defaultMenuItem?.nsitem)
            }
            selfInitiatedSelectionChange = false
            action()
            
        case .Separator:
            break
        }
    }
}
