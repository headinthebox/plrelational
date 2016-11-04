//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational
import Binding
import BindableControls

typealias DB = DocDatabase

class DocDatabase {
    
    typealias Spec = PlistDatabase.RelationSpec
    
    enum Object: String, SchemeEnum { case
        ID = "id",
        ItemType = "type",
        Name = "name"
        static var relationName: String { return "object" }
        static var relationSpec: Spec { return file(path: "objects.plist") }
    }
    
    enum ObjectData: String, SchemeEnum { case
        ID = "id", // Foreign Key: Object.ID
        Created = "created_date",
        Modified = "modified_date",
        LastEditingUser = "last_user",
        LastEditingComputer = "last_computer",
        Value = "value"
        static var relationName: String { return "object_data" }
        static var relationSpec: Spec { return dir(path: "object_data", primaryKey: ObjectData.ID.a) }
    }
    
    enum DocItem: String, SchemeEnum { case
        ID = "id",
        ObjectID = "obj_id", // Foreign Key: Object.ID
        Parent = "parent",
        Order = "order"
        static var relationName: String { return "doc_item" }
        static var relationSpec: Spec { return file(path: "doc_items.plist") }
    }
    
    // TODO: These tab-related relations should be machine- or user-specific
    enum Tab: String, SchemeEnum { case
        ID = "id",
        Order = "order",
        HistoryID = "history_id"   // Foreign Key: TabHistoryItem.ID
        static var relationName: String { return "tab" }
        static var relationSpec: Spec { return file(path: "tabs.plist") }
    }
    
    enum TabHistoryItem: String, SchemeEnum { case
        ID = "id",
        TabID = "tab_id",           // Foreign Key: Tab.ID
        Position = "position",
        Section = "section",
        ObjectID = "obj_id",        // Foreign Key: Object.ID
        DocItemID = "doc_item_id",  // Foreign Key: DocItem.ID
        ItemType = "type"
        static var relationName: String { return "tab_history_item" }
        static var relationSpec: Spec { return file(path: "tab_history_items.plist") }
    }
    
    enum SelectedTab: String, SchemeEnum { case
        ID = "id" // Foreign Key: Tab.ID
        static var relationName: String { return "selected_tab" }
        static var relationSpec: Spec { return file(path: "selected_tabs.plist") }
    }
    
    // XXX: This isn't actually being used in the app and should be removed, but first we would
    // need to update the test code to stop using it for the purposes of performing dummy
    // queries/updates
    enum SelectedInspectorItemID: String, SchemeEnum { case
        ID = "id"
        static var relationName: String { return "selected_inspector_item" }
        static var relationSpec: Spec { return file(path: "selected_inspector_items.plist") }
    }
    
    private(set) var url: URL?
    private let plistDB: PlistDatabase
    private let loggingDB: ChangeLoggingDatabase
    private let transactionalDB: TransactionalDatabase
    private let undoableDB: UndoableDatabase
    
    /// Whether to perform database operations at the transactional/change-logging level, or to
    /// simply operate on the stored database level.
    private let transactional: Bool
    
    static func create(at url: URL?,
                       undoManager: BindableControls.UndoManager,
                       transactional: Bool) -> Result<DocDatabase, DocDatabaseError>
    {
        switch PlistDatabase.create(url, relationSpecs()) {
        case .Ok(let plistDB):
            if !transactional {
                // XXX: Ensure that the destination directory exists before we continue
                if let error = plistDB.validateRelations().err {
                    return .Err(.createFailed(underlying: error))
                }
            }
            
            return .Ok(DocDatabase(url: url, plistDB: plistDB, undoManager: undoManager, transactional: transactional))
            
        case .Err(let error):
            return .Err(.createFailed(underlying: error))
        }
    }
    
    static func open(from url: URL,
                     undoManager: BindableControls.UndoManager,
                     transactional: Bool) -> Result<DocDatabase, DocDatabaseError>
    {
        // TODO: Validate relation files, etc
        switch PlistDatabase.open(url, relationSpecs()) {
        case .Ok(let plistDB):
            return .Ok(DocDatabase(url: url, plistDB: plistDB, undoManager: undoManager, transactional: transactional))
        case .Err(let error):
            return .Err(.openFailed(underlying: error))
        }
    }
    
    private init(url: URL?,
                 plistDB: PlistDatabase,
                 undoManager: BindableControls.UndoManager,
                 transactional: Bool)
    {
        self.url = url
        self.plistDB = plistDB
        self.loggingDB = ChangeLoggingDatabase(plistDB)
        self.transactionalDB = TransactionalDatabase(loggingDB)
        self.undoableDB = UndoableDatabase(db: transactionalDB, undoManager: undoManager)
        self.transactional = transactional
    }
    
    func performUndoableAction(_ name: String, _ transactionFunc: @escaping (Void) -> Void) {
        performUndoableAction(name, before: nil, transactionFunc)
    }
    
    func performUndoableAction(_ name: String, before: ChangeLoggingDatabaseSnapshot?, _ transactionFunc: @escaping (Void) -> Void) {
        if isBusy {
            print("WARNING: Performing action `\(name)` while database is busy; are you sure this is safe?")
        }
        undoableDB.performUndoableAsyncAction(name, before: before, transactionFunc)
    }
    
    func undoableBidiProperty<T>(action: String, signal: Signal<T>, update: @escaping (T) -> Void) -> AsyncReadWriteProperty<T> {
        return undoableDB.asyncBidiProperty(action: action, signal: signal, update: update)
    }
    
    func undoableBidiProperty<T>(action: String, initialValue: T?, signal: Signal<T>, update: @escaping (T) -> Void) -> AsyncReadWriteProperty<T> {
        return undoableDB.asyncBidiProperty(action: action, initialValue: initialValue, signal: signal, update: update)
    }
    
    /// Saves the database to a new location, overwriting and/or deleting any existing files as needed.
    func save(to url: URL) -> Result<(), DocDatabaseError> {
        self.url = url
        plistDB.root = url
        
        // Delete any existing file(s) at the destination
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                return .Err(.replaceFailed(underlying: error as NSError))
            }
        }
        
        // Ensure that database directory has been created and relations have been prepared before we save
        if let validateError = plistDB.validateRelations().err {
            return .Err(.saveFailed(underlying: validateError))
        }
        
        let saveResult = transactional ? loggingDB.save() : plistDB.saveRelations()
        return saveResult.mapErr{ error in .saveFailed(underlying: error) }
    }
    
    /// Saves the database to the current location.
    func save() -> Result<(), DocDatabaseError> {
        precondition(self.url != nil)
        precondition(self.url == plistDB.root)
        
        let saveResult = transactional ? loggingDB.save() : plistDB.saveRelations()
        return saveResult.mapErr{ error in .saveFailed(underlying: error) }
    }
    
    /// Resolves to true when the underlying transactional database is busy updating relations.
    var isBusy: Bool {
        return UpdateManager.currentInstance.state != .idle
    }
    
    /// Resolves to true when the underlying transactional database is *not* busy updating relations, i.e.,
    /// it is safe to submit critical work.
    var isNotBusy: Bool {
        return !isBusy
    }
    
    func storedRelation<S: SchemeEnum>(_ scheme: S.Type) -> StoredRelation {
        return plistDB.storedRelation(forName: scheme.relationName)!
    }
    
    private func transactionalRelation<S: SchemeEnum>(_ scheme: S.Type) -> TransactionalRelation {
        return transactionalDB[scheme.relationName]
    }
    
    // MARK: Raw relation mutation
    
    lazy var objects: TransactionalRelation = self.transactionalRelation(Object.self)
    lazy var objectData: TransactionalRelation = self.transactionalRelation(ObjectData.self)
    lazy var docItems: TransactionalRelation = self.transactionalRelation(DocItem.self)
    lazy var tabs: TransactionalRelation = self.transactionalRelation(Tab.self)
    lazy var selectedTab: TransactionalRelation = self.transactionalRelation(SelectedTab.self)
    lazy var tabHistoryItems: TransactionalRelation = self.transactionalRelation(TabHistoryItem.self)
    
    // XXX
    lazy var selectedInspectorItemIDs: TransactionalRelation = self.transactionalRelation(SelectedInspectorItemID.self)
    
    private func addObject(objectID: ObjectID, name: String, type: ItemType,
                           created: Date, modified: Date,
                           lastUser: String, lastComputer: String,
                           value: RelationValue?)
    {
        if type.isObjectType {
            precondition(value != nil)
        }
        
        let orow: Row = [
            Object.ID.a: objectID.relationValue,
            Object.ItemType.a: RelationValue(type.rawValue),
            Object.Name.a: RelationValue(name)
        ]
        let drow: Row = [
            ObjectData.ID.a: objectID.relationValue,
            ObjectData.Created.a: RelationValue(created.timeIntervalSince1970),
            ObjectData.Modified.a: RelationValue(modified.timeIntervalSince1970),
            ObjectData.LastEditingUser.a: RelationValue(lastUser),
            ObjectData.LastEditingComputer.a: RelationValue(lastComputer),
            ObjectData.Value.a: value ?? .null
        ]
        
        // TODO: Error handling
        if transactional {
            objects.asyncAdd(orow)
            objectData.asyncAdd(drow)
        } else {
            let oresult = storedRelation(Object.self).add(orow)
            if let error = oresult.err {
                print("Failed to add row to `object`: \(error)")
            }
            
            let dresult = storedRelation(ObjectData.self).add(drow)
            if let error = dresult.err {
                print("Failed to add row to `object_data`: \(error)")
            }
        }
    }
    
    func addDocItem(docItemID: DocItemID, objectID: ObjectID, parentID: DocItemID?, order: Double) {
        let row: Row = [
            DocItem.ID.a: docItemID.relationValue,
            DocItem.ObjectID.a: objectID.relationValue,
            DocItem.Parent.a: parentID.map{ $0.relationValue } ?? .null,
            DocItem.Order.a: RelationValue(order)
        ]
        
        // TODO: Error handling
        if transactional {
            docItems.asyncAdd(row)
        } else {
            let result = storedRelation(DocItem.self).add(row)
            if let error = result.err {
                print("Failed to add row to `doc_item`: \(error)")
            }
        }
    }
    
    func addDocObject(docObject: DocObject, name: String,
                      created: Date, modified: Date,
                      lastUser: String, lastComputer: String,
                      value: RelationValue?,
                      parentID: DocItemID?, order: Double)
    {
        addObject(objectID: docObject.objectID, name: name, type: docObject.type,
                  created: created, modified: modified,
                  lastUser: lastUser, lastComputer: lastComputer,
                  value: value)
        
        addDocItem(docItemID: docObject.docItemID, objectID: docObject.objectID,
                   parentID: parentID, order: order)
    }
    
    func deleteDocObject(docItemID: DocItemID) {
        precondition(transactional)
        
        docItems.cascadingDelete(
            DocItem.ID.a *== docItemID.relationValue,
            cascade: { (relation, row) in
                if relation === self.docItems {
                    // Tree delete within docItems (removes all descendants), and delete
                    // the associated object too, but only if this doc item represents
                    // an "original" and not a "reference" to an object
                    let rowDocItemID = row[DocItem.ID.a]
                    let rowObjectID = row[DocItem.ObjectID.a]
                    // TODO: We should probably have an explicit boolean attribute to
                    // indicate whether this is a "reference", instead of comparing
                    // the two IDs
                    let isReference = rowDocItemID != rowObjectID
                    if isReference {
                        // Delete within `doc_item` only
                        // TODO: Only need to cascade the delete within `doc_item` if the row
                        // being deleted is a group or section, but we can't determine that
                        // currently without querying the `object` relation, so for now we have
                        // some wasted effort
                        return [
                            (self.docItems, DocItem.Parent.a *== rowDocItemID),
                            (self.tabHistoryItems, TabHistoryItem.DocItemID.a *== rowDocItemID)
                        ]
                    } else {
                        // Delete within `doc_item` and also cascade delete in `object`
                        return [
                            (self.docItems, DocItem.Parent.a *== rowDocItemID),
                            (self.objects, Object.ID.a *== rowObjectID),
                            (self.tabHistoryItems, TabHistoryItem.DocItemID.a *== rowDocItemID)
                        ]
                    }
                    
                } else if relation === self.objects {
                    // Delete from `object_data` + `tab_history_item`
                    let rowObjectID = row[Object.ID.a]
                    return [
                        (self.objectData, ObjectData.ID.a *== rowObjectID),
                        (self.tabHistoryItems, TabHistoryItem.ObjectID.a *== rowObjectID)
                    ]
                    
                } else {
                    return []
                }
            },
            update: { (relation, row) in
                if relation === self.tabHistoryItems {
                    // Fix up the associated tab's history stack "cursor" if the history item being deleted
                    // is the current one for its tab; first get the ID of the history item that was deleted
                    let deletedHistoryItemID = row[TabHistoryItem.ID.a]
                    
                    // Get the current position of the history item that was deleted
                    let currentPosition = row[TabHistoryItem.Position.a]
                    
                    // Determine the tab associated with the history item that was deleted
                    let tabID = row[TabHistoryItem.TabID.a]
                    
                    // Determine whether the history item that was deleted is the same as the current history
                    // item for that tab; if there's a match, this relation will contain the tab row, otherwise
                    // it will be empty (which will short circuit the update)
                    let matchedTab = self.tabs
                        .select(Tab.ID.a *== tabID *&& Tab.HistoryID.a *== deletedHistoryItemID)
                    
                    // Determine the new history cursor for the tab:
                    //   - If there's no match, `matchedTab` will be empty, so the update will be a no-op
                    //   - If there is a match, but there are no items remaining in the history for the tab, we
                    //     want `newCurrentItemID` to resolve to NULL so that the tab's history cursor is cleared
                    //   - If there is a match, and there are one or more items remaining in the history for that
                    //     tab, we want `newCurrentItemID` to resolve to the next available history item
                    let remainingHistoryItemsForTab = self.tabHistoryItems
                        .select(TabHistoryItem.TabID.a *== tabID)
                    let backItem = remainingHistoryItemsForTab
                        .select(max: TabHistoryItem.Position.a, *<=, currentPosition)
                    let forwardItem = remainingHistoryItemsForTab
                        .select(min: TabHistoryItem.Position.a, *>, currentPosition)
                    let newCurrentItemID = backItem.otherwise(forwardItem)
                        .project(TabHistoryItem.ID.a)
                        .renameAttributes([TabHistoryItem.ID.a: Tab.HistoryID.a])
                        .otherwise(MakeRelation([Tab.HistoryID.a], [.null]))
                    
                    // Set the new "current" history item for the tab
                    return [
                        CascadingUpdate(relation: matchedTab, query: true, attributes: [Tab.HistoryID.a], fromRelation: newCurrentItemID)
                    ]
                } else {
                    return []
                }
            },
            completionCallback: { _ in
                // TODO: Error handling?
            }
        )
    }
    
    func updateDocItemOrder(docItemID: DocItemID, order: Double) {
        precondition(!transactional)
        
        // XXX: Compiler seems to crash if we attempt to call the synchronous `update` variant
        // (which is declared as `mutating`) through the StoredRelation protocol, have to
        // downcast to a concrete type as a workaround
        let r = storedRelation(DocItem.self) as! PlistFileRelation
        _ = r.update(DocItem.ID.a *== docItemID.relationValue, newValues: [
            DocItem.Order.a: RelationValue(order)
        ])
    }
    
    func addTab(tabID: TabID, historyItemID: HistoryItemID?, order: Double) {
        let row: Row = [
            Tab.ID.a: tabID.relationValue,
            Tab.Order.a: RelationValue(order),
            Tab.HistoryID.a: historyItemID?.relationValue ?? .null,
            ]
        
        // TODO: Error handling
        if transactional {
            tabs.asyncAdd(row)
        } else {
            let result = storedRelation(Tab.self).add(row)
            if let error = result.err {
                print("Failed to add to `tab`: \(error)")
            }
        }
    }
    
    func deleteTab(tabID: TabID, thenSelect nextTabID: TabID?) {
        precondition(transactional)
        
        let id = tabID.relationValue
        tabs.asyncDelete(Tab.ID.a *== id)
        tabHistoryItems.asyncDelete(TabHistoryItem.TabID.a *== id)
        if let nextTabID = nextTabID {
            setSelectedTab(tabID: nextTabID)
        }
    }
    
    func deleteTabs(otherThan tabID: TabID) {
        precondition(transactional)
        
        let id = tabID.relationValue
        tabs.asyncDelete(Tab.ID.a *!= id)
        tabHistoryItems.asyncDelete(TabHistoryItem.TabID.a *!= id)
        setSelectedTab(tabID: tabID)
    }
    
    func setSelectedTab(tabID: TabID?) {
        let rows: [Row]
        if let tabID = tabID {
            let row: Row = [
                SelectedTab.ID.a: tabID.relationValue
            ]
            rows = [row]
        } else {
            rows = []
        }
        
        if transactional {
            selectedTab.asyncReplaceRows(rows)
        } else {
            // TODO: Error handling
            storedRelation(SelectedTab.self).replaceRows(rows)
        }
    }
    
    func selectDocOutlineItem(tabID: TabID, path: DocOutlinePath, currentPosition: Int64?) -> HistoryItemID {
        precondition(transactional)
        
        if let position = currentPosition {
            // If we are positioned somewhere in the middle of the navigation stack (e.g. if the user clicked
            // the "Back" button a couple times), we first need to clear the items that existed above the current
            // one on the stack
            tabHistoryItems.asyncDelete(TabHistoryItem.TabID.a *== tabID.relationValue *&& TabHistoryItem.Position.a *> RelationValue(position))
        }
        
        // Push a new history item onto the stack
        let newPosition = (currentPosition ?? 0) + 1
        let historyItemID = HistoryItemID()
        let row = path.toRow(id: historyItemID, tabID: tabID, position: newPosition)
        tabHistoryItems.asyncAdd(row)
        tabs.asyncUpdate(Tab.ID.a *== tabID.relationValue, newValues: [Tab.HistoryID.a: historyItemID.relationValue])
        return historyItemID
    }
    
    func setHistoryItem(historyItemID: HistoryItemID, forTab tabID: TabID) {
        precondition(transactional)
        
        tabs.asyncUpdate(Tab.ID.a *== tabID.relationValue, newValues: [Tab.HistoryID.a: historyItemID.relationValue])
    }
    
    /// The current object for each tab.
    lazy var tabObjects: Relation = {
        // Join Tab + TabHistoryItem to get the current history item for each tab; if a tab has no history,
        // there will be NULL values for each TabHistoryItem attribute
        let tabHistoryItems = self.tabHistoryItems
            .renameAttributes([TabHistoryItem.ID.a: Tab.HistoryID.a])
        let currentHistoryItemForEachTab = self.tabs
            .renameAttributes([Tab.ID.a: TabHistoryItem.TabID.a])
            .leftOuterJoin(tabHistoryItems)
        
        // Join Tab + TabHistoryItem + Object to get the current object ID/name for each tab; if a tab has
        // no history, there will be NULL values for each Object attribute
        return currentHistoryItemForEachTab
            .project([TabHistoryItem.TabID.a, TabHistoryItem.ObjectID.a, Tab.Order.a])
            .renameAttributes([TabHistoryItem.ObjectID.a: Object.ID.a])
            .leftOuterJoin(self.objects)
    }()
    
    /// All history items for the active tab.
    lazy var selectedTabHistoryItems: Relation = {
        // Join SelectedTab + TabHistoryItem to get all history items for the active tab
        return self.selectedTab
            .renameAttributes([SelectedTab.ID.a: TabHistoryItem.TabID.a])
            .join(self.tabHistoryItems)
    }()
    
    /// The current history item for the active tab.
    lazy var selectedTabCurrentHistoryItem: Relation = {
        // Join Tab + SelectedTab + TabHistoryItem to get the current history item for the active tab
        // if there is no active tab, or if the active tab has no history, the relation will be empty
        return self.tabs
            .renameAttributes([Tab.ID.a: TabHistoryItem.TabID.a])
            .equijoin(self.selectedTabHistoryItems, matching: [Tab.HistoryID.a: TabHistoryItem.ID.a])
    }()
    
    /// The object associated with current history item for the active tab.
    lazy var selectedTabCurrentObject: Relation = {
        // Join Tab + SelectedTab + TabHistoryItem + Object to get the current object for the active tab
        // if there is no active tab, or if the active tab has no history, the relation will be empty
        return self.selectedTabCurrentHistoryItem
            .project(TabHistoryItem.ObjectID.a)
            .renameAttributes([TabHistoryItem.ObjectID.a: Object.ID.a])
            .join(self.objects)
    }()
    
    // MARK: Undoable actions
    
    func objectNameReadOnlyProperty(objectID: ObjectID, initialValue: String?) -> AsyncReadableProperty<String?> {
        return self.objects
            .select(DB.Object.ID.a *== objectID.relationValue)
            .project(DB.Object.Name.a)
            .asyncProperty(initialValue: initialValue, { $0.oneStringOrNil($1) })
    }
    
    func objectNameReadWriteProperty(objectID: ObjectID, initialValue: String?) -> AsyncReadWriteProperty<String?> {
        let relation = self.objects
            .select(Object.ID.a *== objectID.relationValue)
            .project(Object.Name.a)
        // TODO: s/Item/type.name/
        return undoableBidiProperty(
            action: "Rename Item",
            initialValue: initialValue,
            signal: relation.signal{ $0.oneStringOrNil($1) },
            update: { relation.asyncUpdateNullableString($0) }
        )
    }
    
    func deleteDocObjectAction(docItemID: DocItemID, type: ItemType) {
        performUndoableAction("Delete \(type.name)", {
            self.deleteDocObject(docItemID: docItemID)
        })
    }
    
    // MARK: Relation creation
    
    private static func relationSpecs() -> [PlistDatabase.RelationSpec] {
        return [
            Object.relationSpec,
            ObjectData.relationSpec,
            DocItem.relationSpec,
            Tab.relationSpec,
            TabHistoryItem.relationSpec,
            SelectedTab.relationSpec,
            // XXX
            SelectedInspectorItemID.relationSpec
        ]
    }
    
    // XXX: This is temporary
    func addDefaultData() {
        precondition(transactional)
        
        // Create the default (implicit) tab
        let tab0 = TabID()
        addTab(tabID: tab0, historyItemID: nil, order: 5.0)
        setSelectedTab(tabID: tab0)
        
        // XXX: Wait for async updates to finish before we continue
        let runloop = CFRunLoopGetCurrent()
        let stateObserverRemover = UpdateManager.currentInstance.addStateObserver({
            if $0 == .idle {
                CFRunLoopStop(runloop)
            }
        })
        CFRunLoopRun()
        stateObserverRemover()
    }
}

extension DocOutlinePath {
    /// Converts this path to a Row that is compatible with the TabHistoryItem scheme.
    func toRow(id: HistoryItemID, tabID: TabID, position: Int64) -> Row {
        let sectionID: DocOutlineSectionID
        let objectID: ObjectID
        let docItemID: DocItemID?
        let tagID: ObjectID?
        let type: ItemType
        switch self {
        case let .homePage(oid, t):
            sectionID = .home
            objectID = oid
            docItemID = nil
            tagID = nil
            type = t
        case let .userPage(did, oid, t):
            sectionID = .userPages
            objectID = oid
            docItemID = did
            tagID = nil
            type = t
        case let .taggedPage(tid, oid, t):
            sectionID = .tags
            objectID = oid
            docItemID = nil
            tagID = tid
            type = t
        }
        return [
            DB.TabHistoryItem.ID.a: id.relationValue,
            DB.TabHistoryItem.TabID.a: tabID.relationValue,
            DB.TabHistoryItem.Section.a: RelationValue(sectionID.rawValue),
            DB.TabHistoryItem.ObjectID.a: objectID.relationValue,
            DB.TabHistoryItem.DocItemID.a: docItemID?.relationValue ?? .null,
            DB.TabHistoryItem.TagID.a: tagID?.relationValue ?? .null,
            DB.TabHistoryItem.ItemType.a: RelationValue(type.rawValue),
            DB.TabHistoryItem.Position.a: RelationValue(position)
        ]
    }
}

extension HistoryItem {
    /// Extracts a HistoryItem from a Row that originated from the TabHistoryItem relation.
    static func fromRow(_ row: Row) -> HistoryItem {
        let id = HistoryItemID(row[DB.TabHistoryItem.ID.a])
        let tabID = TabID(row[DB.TabHistoryItem.TabID.a])
        let position: Int64 = row[DB.TabHistoryItem.Position.a].get()!
        
        let sectionID = DocOutlineSectionID(row[DB.TabHistoryItem.Section.a])!
        let objectID = ObjectID.fromNullable(row[DB.TabHistoryItem.ObjectID.a])
        let docItemID = DocItemID.fromNullable(row[DB.TabHistoryItem.DocItemID.a])
        let type = ItemType(row[DB.TabHistoryItem.ItemType.a])!
        let outlinePath: DocOutlinePath
        switch sectionID {
        case .home:
            outlinePath = .homePage(objectID: objectID!, type: type)
        case .userPages:
            outlinePath = .userPage(docItemID: docItemID!, objectID: objectID!, type: type)
        case .tags:
            outlinePath = .taggedPage(tagID: tagID!, objectID: objectID!, type: type)
        }
        
        return HistoryItem(id: id, tabID: tabID, outlinePath: outlinePath, position: position)
    }
}

protocol SchemeEnum: Hashable {
    var rawValue: String { get }
    static var relationName: String { get }
    static var relationSpec: PlistDatabase.RelationSpec { get }
}

extension SchemeEnum {
    // From: http://stackoverflow.com/a/32429125
    fileprivate static func cases() -> AnySequence<Self> {
        precondition(MemoryLayout<Self>.size <= 1, "Don't know how to deal with enums larger than one byte here")
        if MemoryLayout<Self>.size == 0 {
            let theOnlyCase = unsafeBitCast((), to: Self.self)
            return AnySequence([theOnlyCase])
        }
        
        typealias S = Self
        return AnySequence { () -> AnyIterator<S> in
            // Scream. Can we do this better? This assumes cases start from 0 and that we're always
            // one byte.
            var raw: UInt8 = 0
            return AnyIterator {
                let current = unsafeBitCast(raw, to: Self.self)
                guard current.hashValue == Int(raw) else { return nil }
                raw += 1
                return current
            }
        }
    }
    
    var a: Attribute {
        return Attribute(rawValue)
    }
    
    static var scheme: Scheme {
        return Scheme(attributes: Set(Self.cases().map{ $0.a }))
    }
    
    static func file(path: String) -> PlistDatabase.RelationSpec {
        return .file(name: relationName, path: path, scheme: scheme)
    }
    
    static func dir(path: String, primaryKey: Attribute) -> PlistDatabase.RelationSpec {
        return .directory(name: relationName, path: path, scheme: scheme, primaryKey: primaryKey)
    }
}

// TODO: Move this to libRelational
extension Relation {
    
    /// Selects all rows that pass the comparison test (e.g. <= `value`), and then from that set of rows,
    /// selects the row(s) whose value for the given attribute is the maximum value.
    func select(max attribute: Attribute,
                _ compareFunc: (SelectExpression, SelectExpression) -> SelectExpression,
                _ value: RelationValue) -> Relation
    {
        let selected = self.select(compareFunc(attribute, value))
        let maxOfSelected = selected.max(attribute)
        return maxOfSelected.join(selected)
    }
    
    /// Selects all rows that pass the comparison test (e.g. >= `value`), and then from that set of rows,
    /// selects the row(s) whose value for the given attribute is the minimum value.
    func select(min attribute: Attribute,
                _ compareFunc: (SelectExpression, SelectExpression) -> SelectExpression,
                _ value: RelationValue) -> Relation
    {
        let selected = self.select(compareFunc(attribute, value))
        let minOfSelected = selected.min(attribute)
        return minOfSelected.join(selected)
    }
}

