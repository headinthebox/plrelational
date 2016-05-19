//
//  DocModel.swift
//  Relational
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational

// TODO: Similar to what we did with `globalID`, we put all "type" constants that describe
// collections and objects into the same space, even though it would be more appropriate
// to have a `CollectionType` that is distinct from `ObjectType`.
enum ItemType: Int64 { case
    Group = 0,
    Collection = 1,
    Page = 2,
    Text = 3,
    Image = 4
    
    var name: String {
        switch self {
        case .Group: return "Group"
        case .Collection: return "Collection"
        case .Page: return "Page"
        case .Text: return "Text"
        case .Image: return "Image"
        }
    }
    
    var isCollectionType: Bool {
        switch self {
        case .Group, .Collection, .Page:
            return true
        default:
            return false
        }
    }
    
    var isObjectType: Bool {
        return !isCollectionType
    }
}

struct DocItem {
    let id: RelationValue
    let type: ItemType
}

class DocModel {

    private let undoManager: UndoManager
    private let db: TransactionalDatabase

    private var collections: MutableRelation
    private var objects: MutableRelation
    private var selectedCollectionID: MutableRelation
    private var selectedInspectorItemIDs: MutableRelation
    
    private let inspectorItems: Relation
    private let selectedCollection: Relation
    private let selectedInspectorItems: Relation
    private let selectedItems: Relation

    private let docOutlineBinding: OrderedTreeBinding
    private let inspectorItemsBinding: OrderedTreeBinding
    
    // TODO: To simplify implementation of the relation that controls the inspector tree view,
    // we put identifiers for both the `collection` and `object` relations into the same set.
    // A potentially better/safer alternative would be to introduce compound primary key
    // support into OrderedTreeBinding so that we can more easily merge data from different
    // source relations into a single relation.
    private var globalID: Int64 = 1
    
    private var removal: (Void -> Void)!
    
    init(undoManager: UndoManager) {
        self.undoManager = undoManager
        
        func makeDB() -> (path: String, db: SQLiteDatabase) {
            let tmp = NSTemporaryDirectory() as NSString
            let dbname = "testing-\(NSUUID()).db"
            let path = tmp.stringByAppendingPathComponent(dbname)
            _ = try? NSFileManager.defaultManager().removeItemAtPath(path)
            
            let db = try! SQLiteDatabase(path)
            
            return (path, db)
        }
        
        // Prepare the stored relations
        let sqliteDB = makeDB().db
        let db = TransactionalDatabase(sqliteDB)
        func createRelation(name: String, _ scheme: Scheme) -> MutableRelation {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return db[name]
        }
        self.collections = createRelation("collection", ["id", "type", "name", "parent", "order"])
        self.objects = createRelation("object", ["id", "type", "name", "coll_id", "order"])
        self.selectedCollectionID = createRelation("selected_collection", ["coll_id"])
        self.selectedInspectorItemIDs = createRelation("selected_inspector_item", ["item_id"])

        // Prepare the higher level relations
        self.selectedCollection = collections.renameAttributes(["id" : "coll_id"]).join(selectedCollectionID)
        
        // The `inspectorItems` relation is a view that presents the currently selected collection
        // (from the doc outline tree view) as the root node with its associated objects as the
        // root node's children
        // TODO: This is probably more complex than it needs to be
        let inspectorCollectionItems = selectedCollection
            .project(["coll_id", "type", "name"])
            .renameAttributes(["coll_id": "id"])
            .join(MakeRelation(["parent", "order"], [.NULL, 5.0]))
        let inspectorObjectItems = selectedCollectionID
            .project(["coll_id"])
            .join(objects)
            .renameAttributes(["coll_id": "parent"])
            .project(["id", "type", "name", "parent", "order"])
        self.inspectorItems = inspectorCollectionItems.union(inspectorObjectItems)
        self.selectedInspectorItems = inspectorItems.renameAttributes(["id" : "item_id"]).join(selectedInspectorItemIDs)
        
        // The `selectedItems` relation is a roll-up view that includes the currently selected
        // inspector item(s) and/or the currently selected doc outline item.  The inspector item(s)
        // have a higher priority value associated with them, so that finding the currently selected
        // items is just a matter of choosing the rows with the highest priority value.
        let selectedCollectionWithPriority = selectedCollection
            .renameAttributes(["coll_id": "id"])
            .project(["id", "type", "name"])
            .join(MakeRelation(["priority"], [1]))
        let selectedInspectorItemsWithPriority = selectedInspectorItems
            .renameAttributes(["item_id": "id"])
            .project(["id", "type", "name"])
            .join(MakeRelation(["priority"], [2]))
        let allSelectedItems = selectedCollectionWithPriority.union(selectedInspectorItemsWithPriority)
        self.selectedItems = allSelectedItems.max("priority").join(allSelectedItems)

        // Prepare the tree bindings
        self.docOutlineBinding = OrderedTreeBinding(relation: collections, idAttr: "id", parentAttr: "parent", orderAttr: "order")
        self.inspectorItemsBinding = OrderedTreeBinding(relation: inspectorItems, idAttr: "id", parentAttr: "parent", orderAttr: "order")
        
        self.db = db

        self.removal = selectedItems.addChangeObserver({ changes in
//            print("ADDS:\n\(changes.added)")
//            print("REMOVES:\n\(changes.removed)")
            print("ITEMS:\n\(self.selectedItems)\n")
        })
    }
    
    func addDefaultData() {
        func addCollection(collectionID: Int64, name: String, type: ItemType, parentID: Int64?, previousID: Int64?) {
            db.transaction({
                self.addCollection(collectionID, name: name, type: type, parentID: parentID, previousID: previousID)
            })
        }
        
        addCollection(1, name: "Group1", type: .Group, parentID: nil, previousID: nil)
        addCollection(2, name: "Collection1", type: .Collection, parentID: 1, previousID: nil)
        addCollection(3, name: "Page1", type: .Page, parentID: 1, previousID: 2)
        addCollection(4, name: "Page2", type: .Page, parentID: 1, previousID: 3)
        addCollection(5, name: "Child1", type: .Page, parentID: 2, previousID: nil)
        addCollection(6, name: "Child2", type: .Page, parentID: 2, previousID: 5)
        addCollection(7, name: "Group2", type: .Group, parentID: nil, previousID: 1)
        
        func addObject(objectID: Int64, name: String, type: ItemType, collectionID: Int64, order: Double) {
            db.transaction({
                self.addObject(objectID, name: name, type: type, collectionID: collectionID, order: order)
            })
        }
        
        addObject(8, name: "Text1", type: .Text, collectionID: 3, order: 5.0)
        addObject(9, name: "Image1", type: .Image, collectionID: 3, order: 7.0)
        globalID = 10
    }
    
    private func performUndoableAction(name: String, _ transactionFunc: Void -> Void) {
        let (before, after) = db.transactionWithSnapshots(transactionFunc)
        undoManager.registerChange(
            name: name,
            perform: false,
            forward: {
                self.db.restoreSnapshot(after)
            },
            backward: {
                self.db.restoreSnapshot(before)
            }
        )
    }
    
    private func addCollection(collectionID: Int64, name: String, type: ItemType, parentID: Int64?, previousID: Int64?) {
        let row: Row = [
            "id": RelationValue(collectionID),
            "type": RelationValue(type.rawValue),
            "name": RelationValue(name)
        ]
        let parent = parentID.map{RelationValue($0)}
        let previous = previousID.map{RelationValue($0)}
        let pos = TreePos(parentID: parent, previousID: previous, nextID: nil)
        docOutlineBinding.insert(row, pos: pos)
    }
    
    private func addObject(objectID: Int64, name: String, type: ItemType, collectionID: Int64, order: Double) {
        let row: Row = [
            "id": RelationValue(objectID),
            "name": RelationValue(name),
            "type": RelationValue(type.rawValue),
            "coll_id": RelationValue(collectionID),
            "order": RelationValue(order)
        ]
        objects.add(row)
    }

    func newCollection(name: String, type: ItemType, parentID: Int64?) {
        let id = globalID
        globalID += 1
        performUndoableAction("New \(type.name)", {
            self.addCollection(id, name: name, type: type, parentID: parentID, previousID: nil)
        })
    }
    
    func newObject(name: String, type: ItemType, collectionID: Int64, order: Double) {
        let id = globalID
        globalID += 1
        performUndoableAction("New \(type.name)", {
            self.addObject(id, name: name, type: type, collectionID: collectionID, order: order)
        })
    }
    
    func deleteCollection(id: RelationValue, type: ItemType) {
        performUndoableAction("Delete \(type.name)", {
            self.docOutlineBinding.delete(id)
        })
    }

    private func selectDocOutlineItems(ids: [RelationValue]) {
        // TODO: s/Collection/type.name/
        // TODO: "Deselect"?
        self.performUndoableAction("Select Collection", {
            // TODO: This could probably be made more efficient
            self.selectedCollectionID.delete(true)
            for id in ids {
                self.selectedCollectionID.add(["coll_id": id])
            }
        })
    }

    private func selectInspectorItems(ids: [RelationValue]) {
        // TODO: s/Object/type.name/
        // TODO: "Deselect"?
        self.performUndoableAction("Select Object", {
            // TODO: This could probably be made more efficient
            self.selectedInspectorItemIDs.delete(true)
            for id in ids {
                self.selectedInspectorItemIDs.add(["item_id": id])
            }
        })
    }
    
    lazy var docOutlineTreeViewModel: TreeViewModel = { [unowned self] in
        let data = TreeViewModel.Data(
            binding: self.docOutlineBinding,
            allowsChildren: { row in
                let type = ItemType(rawValue: row["type"].get()!)!
                return type == .Group || type == .Collection
            },
            contextMenu: { row in
                let collectionID = row["id"]
                let collectionType = ItemType(rawValue: row["type"].get()!)!
                return ContextMenu(items: [
                    .Titled(title: "New Page", action: { self.newCollection("Page", type: .Page, parentID: nil) }),
                    .Separator,
                    .Titled(title: "Delete", action: { self.deleteCollection(collectionID, type: collectionType) })
                ])
            },
            move: { (srcPath, dstPath) in
                // TODO: s/Collection/type.name/
                self.performUndoableAction("Move Collection", {
                    self.docOutlineBinding.move(srcPath: srcPath, dstPath: dstPath)
                })
            }
        )
        
        let selection = TreeViewModel.Selection(
            relation: self.selectedCollectionID,
            set: { ids in
                self.selectDocOutlineItems(ids)
            },
            get: {
                return self.selectedCollectionID.rows().map{$0.ok!["coll_id"]}
            }
        )
        
        let cell = { (row: Row) -> TreeViewModel.Cell in
            // TODO: Ideally we'd have a way to create a projection Relation directly from
            // an existing Row.  In the meantime, we'll select/project from the original
            // relation.  The downside of that latter approach is that the cell text will
            // disappear before the cell fades out in the case where the item is deleted.
            // (If the cell was bound to a projection of the row, presumably it would
            // continue to work even after the row has been deleted from the underlying
            // relation.)
            let rowID = row["id"]
            let type = ItemType(rawValue: row["type"].get()!)!
            let nameRelation = self.collections.select(Attribute("id") *== rowID).project(["name"])
            let binding = self.bidiBinding(nameRelation, type: type.name)
            return TreeViewModel.Cell(text: binding)
        }
        
        return TreeViewModel(data: data, selection: selection, cell: cell)
    }()

    lazy var inspectorTreeViewModel: TreeViewModel = { [unowned self] in
        let data = TreeViewModel.Data(
            binding: self.inspectorItemsBinding,
            allowsChildren: { row in
                let type = ItemType(rawValue: row["type"].get()!)!
                return type.isCollectionType
            },
            contextMenu: nil,
            move: nil
        )
        
        let selection = TreeViewModel.Selection(
            relation: self.selectedCollectionID,
            set: { ids in
                self.selectInspectorItems(ids)
            },
            get: {
                return self.selectedInspectorItemIDs.rows().map{$0.ok!["item_id"]}
            }
        )
        
        let cell = { (row: Row) -> TreeViewModel.Cell in
            let rowID = row["id"]
            let type = ItemType(rawValue: row["type"].get()!)!
            let nameRelation = self.inspectorItems.select(Attribute("id") *== rowID).project(["name"])
            let binding = self.bidiBinding(nameRelation, type: type.name)
            return TreeViewModel.Cell(text: binding)
        }
        
        return TreeViewModel(data: data, selection: selection, cell: cell)
    }()
    
    private lazy var selectedDocItems: ValueBinding<[DocItem]> = { [unowned self] in
        return MultiRowBinding(relation: self.selectedItems).map{ rows in
            return rows.map { row in
                let id = row["id"]
                let type = ItemType(rawValue: row["type"].get()!)!
                return DocItem(id: id, type: type)
            }
        }
    }()
    
    lazy var itemSelected: ValueBinding<Bool> = { [unowned self] in
        return self.selectedDocItems.map{ $0.count > 0 }
    }()
    
    lazy var itemNotSelected: ValueBinding<Bool> = { [unowned self] in
        return self.selectedDocItems.map{ $0.count == 0 }
    }()

    lazy var selectedItemType: ValueBinding<String?> = { [unowned self] in
        return self.selectedDocItems.map{ items -> String? in
            if items.count == 0 {
                return nil
            } else if items.count == 1 {
                return items[0].type.name
            } else {
                let types = Set(items.map{$0.type})
                if types.count == 1 {
                    return "Multiple \(types.first!.name)s"
                } else {
                    return "Multiple Items"
                }
            }
        }
    }()
    
    lazy var selectedItemName: StringBidiBinding = { [unowned self] in
        let nameRelation = self.selectedItems.project(["name"])
        // TODO: s/Collection/type.name/
        return self.bidiBinding(nameRelation, type: "Collection")
    }()
    
    private func bidiBinding(relation: Relation, type: String) -> StringBidiBinding {
        let attr = relation.scheme.attributes.first!
        
        func update(newValue: String) {
            let values: Row = [attr: RelationValue(newValue)]
            Swift.print("UPDATE: \(newValue)")
            var mutableRelation = relation
            let updateResult = mutableRelation.update(true, newValues: values)
            precondition(updateResult.ok != nil)
        }
        
        return StringBidiBinding(relation: relation, change: BidiChange<String>{ (newValue, oldValue, commit) in
            Swift.print("\(commit ? "COMMIT" : "CHANGE") new=\(newValue) old=\(oldValue)")
            if commit {
                self.undoManager.registerChange(
                    name: "Rename \(type)",
                    perform: true,
                    forward: { update(newValue) },
                    backward: { update(oldValue) }
                )
            } else {
                update(newValue)
            }
        })
    }
    
//    private func bidiBinding2(relation: Relation, type: String) -> StringBidiBinding {
//        let attr = relation.scheme.attributes.first!
//        
//        func update(newValue: String) {
//            let values: Row = [attr: RelationValue(newValue)]
//            Swift.print("UPDATE: \(newValue)")
//            var mutableRelation = relation
//            let updateResult = mutableRelation.update(true, newValues: values)
//            precondition(updateResult.ok != nil)
//        }
//
//        return StringBidiBinding(
//            relation: relation,
//            snapshot: {
//                return self.db.takeSnapshot()
//            },
//            change: { newValue in
//                update(nil, newValue)
//            },
//            commit: { before, newValue in
//                self.db.transaction({ update($0, newValue) })
//                let after = self.db.takeSnapshot()
//                self.undoManager.registerChange(
//                    name: "Rename \(type)",
//                    perform: false,
//                    forward: {
//                        self.db.restoreSnapshot(after)
//                    },
//                    backward: {
//                        self.db.restoreSnapshot(before)
//                    }
//                )
//            }
//        )
//    }
}
