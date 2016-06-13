//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational
import Binding

class TextObjectPropertiesModel {
    
    let db: UndoableDatabase
    let selectedTextObjects: Relation
    
    /// - Parameters:
    ///     - db: The database.
    ///     - selectedTextObjects: Relation with scheme [id, editable, hint, font].
    init(db: UndoableDatabase, selectedTextObjects: Relation) {
        self.db = db
        self.selectedTextObjects = selectedTextObjects
    }

    private lazy var editableRelation: Relation = { [unowned self] in
        return self.selectedTextObjects.project(["editable"])
    }()

    private lazy var hintRelation: Relation = { [unowned self] in
        return self.selectedTextObjects.project(["hint"])
    }()

    private lazy var fontRelation: Relation = { [unowned self] in
        return self.selectedTextObjects.project(["font"])
    }()

    lazy var editable: MutableObservableValue<Checkbox.CheckState> = { [unowned self] in
        return self.db.observe(
            self.editableRelation,
            action: "Change Editable",
            get: { Checkbox.CheckState($0.oneBoolOrNil) },
            set: { self.editableRelation.updateBoolean($0.boolValue) }
        )
    }()
    
    lazy var hint: MutableObservableValue<String> = { [unowned self] in
        return self.db.observe(
            self.hintRelation,
            action: "Change Hint",
            get: { $0.oneString },
            set: { self.hintRelation.updateString($0) }
        )
    }()
    
    lazy var hintPlaceholder: ObservableValue<String> = { [unowned self] in
        return self.hintRelation.stringWhenMulti("Multiple Values")
    }()
    
    var availableFonts: [String] = ["Futura", "Helvetica", "Monaco"]
    
    lazy var font: MutableObservableValue<String?> = { [unowned self] in
        return self.db.observe(
            self.fontRelation,
            action: "Change Font",
            get: { $0.oneStringOrNil },
            set: { self.fontRelation.updateNullableString($0) }
        )
    }()
    
    lazy var fontPlaceholder: ObservableValue<String> = { [unowned self] in
        return self.fontRelation.stringWhenMulti("Multiple", otherwise: "Default")
    }()
}
