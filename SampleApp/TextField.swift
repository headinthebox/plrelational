//
//  TextField.swift
//  Relational
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

class TextField: NSTextField, NSTextFieldDelegate {

    private let bindings = BindingSet()

    var string: ValueBinding<String>? {
        didSet {
            bindings.register("string", string, { [weak self] value in
                guard let weakSelf = self else { return }
                if weakSelf.selfInitiatedStringChange { return }
                weakSelf.stringValue = value
            })
        }
    }

    var placeholder: ValueBinding<String>? {
        didSet {
            bindings.register("placeholder", placeholder, { [weak self] value in
                self?.placeholderString = value
            })
        }
    }

    var visible: ValueBinding<Bool>? {
        didSet {
            bindings.register("visible", visible, { [weak self] value in
                self?.hidden = !value
            })
        }
    }
    
    private var previousCommittedValue: String?
    private var previousValue: String?
    private var selfInitiatedStringChange = false
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        
        self.delegate = self
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.delegate = self
    }
    
    override func controlTextDidBeginEditing(obj: NSNotification) {
        //Swift.print("CONTROL DID BEGIN EDITING!")
        previousCommittedValue = stringValue
        previousValue = stringValue
    }
    
    override func controlTextDidChange(notification: NSNotification) {
        //Swift.print("CONTROL DID CHANGE!")
        if let bidiBinding = string as? BidiValueBinding {
            selfInitiatedStringChange = true
            bidiBinding.update(stringValue)
            selfInitiatedStringChange = false
        }
        previousValue = stringValue
    }
    
    override func controlTextDidEndEditing(obj: NSNotification) {
        // Note that controlTextDidBeginEditing may not be called if the user gives focus to the text field
        // but resigns first responder without typing anything, so we only commit the value if the user
        // actually typed something that differs from the previous value
        //Swift.print("CONTROL DID END EDITING!")
        if let previousCommittedValue = previousCommittedValue, bidiBinding = string as? BidiValueBinding {
            // TODO: Need to discard `before` snapshot if we're skipping the commit
            if stringValue != previousCommittedValue {
                selfInitiatedStringChange = true
                bidiBinding.commit(stringValue)
                selfInitiatedStringChange = false
            }
        }
        previousCommittedValue = nil
        previousValue = nil
    }
}
