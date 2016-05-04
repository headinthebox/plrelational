//
//  Binding.swift
//  Relational
//
//  Created by Chris Campbell on 5/3/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational

public struct Change<T> {
    let f: (newValue: T, oldValue: T, commit: Bool) -> Void
}

public class Binding {
    
    public enum Error: ErrorType {
        case NoRows
    }

    let relation: Relation
    let attribute: Attribute
    
    init(relation: Relation, attribute: Attribute) {
        self.relation = relation
        self.attribute = attribute
    }
}

public class BidiBinding<T>: Binding {
    private let change: Change<T>
    
    init(relation: Relation, attribute: Attribute, change: Change<T>) {
        self.change = change
        super.init(relation: relation, attribute: attribute)
    }
    
    public func get() -> Result<RelationValue, RelationError> {
        return relation.rows().generate().next()?.map({ $0[attribute] }) ?? .Err(Error.NoRows)
    }
    
    public func change(newValue newValue: T, oldValue: T) {
        change.f(newValue: newValue, oldValue: oldValue, commit: false)
    }
    
    public func commit(newValue newValue: T, oldValue: T) {
        change.f(newValue: newValue, oldValue: oldValue, commit: true)
    }
}

public struct Pos {
    let previousID: RelationValue?
    let nextID: RelationValue?
}

public protocol OrderedBindingObserver: class {
    func onInsert(index: Int)
    func onDelete(index: Int)
    func onMove(srcIndex srcIndex: Int, dstIndex: Int)
}

public class OrderedBinding {
    
    let relation: SQLiteTableRelation
    let idAttr: Attribute
    private let orderAttr: Attribute

    private(set) public var rows: [Box<Row>] = []
    
    private var observers: [OrderedBindingObserver] = []

    init(relation: SQLiteTableRelation, idAttr: Attribute, orderAttr: Attribute) {
        self.relation = relation
        self.idAttr = idAttr
        self.orderAttr = orderAttr
        
        // TODO: Error handling
        let unsortedRows = relation.rows().map{$0.ok!}
        let sortedRows = unsortedRows.sort({ (row0, row1) in
            let o0: Double = row0[orderAttr].get()!
            let o1: Double = row1[orderAttr].get()!
            return o0 < o1
        })
        self.rows = sortedRows.map{Box($0)}
    }
    
    public func addObserver(observer: OrderedBindingObserver) {
        if observers.indexOf({$0 === observer}) == nil {
            observers.append(observer)
        }
    }

    public func append(row: Row) {
        let lastID = rows.last.map{$0.value[idAttr]}
        insert(row, pos: Pos(previousID: lastID, nextID: nil))
    }
    
    public func insert(row: Row, pos: Pos) {
        var mutableRow = row
        let order = orderForPos(pos)
        mutableRow[orderAttr] = order
        relation.add(mutableRow)

        // XXX
        var index = 0
        for r in rows {
            let o: Double = r.value[orderAttr].get()!
            if o > order.get()! {
                break
            }
            index += 1
        }
        if index < rows.count {
            rows.insert(Box(mutableRow), atIndex: index)
        } else {
            rows.append(Box(mutableRow))
        }
        observers.forEach{$0.onInsert(index)}
    }
    
    public func delete(id: RelationValue) {
        if let index = indexForID(id) {
            relation.delete([.EQ(idAttr, id)])
            rows.removeAtIndex(index)
            observers.forEach{$0.onDelete(index)}
        }
    }
    
    /// Note: dstIndex is relative to the state of the array *after* the item is removed.
    public func move(srcIndex srcIndex: Int, dstIndex: Int) {
        let row = rows.removeAtIndex(srcIndex)
        rows.insert(row, atIndex: dstIndex)
        
        // XXX: This is embarrassing
        let previousID: RelationValue?
        if dstIndex == 0 {
            previousID = nil
        } else {
            let previousRow = rows[dstIndex - 1].value
            previousID = previousRow[idAttr]
        }
        let nextID: RelationValue?
        if dstIndex >= rows.count - 1 {
            nextID = nil
        } else {
            let nextRow = rows[dstIndex + 1].value
            nextID = nextRow[idAttr]
        }
        
        let newPos = Pos(previousID: previousID, nextID: nextID)
        let newOrder = orderForPos(newPos)
        row.value[orderAttr] = newOrder
        
        // TODO: Update the underlying table too
        
        observers.forEach{$0.onMove(srcIndex: srcIndex, dstIndex: dstIndex)}
    }
    
    public func orderForPos(pos: Pos) -> RelationValue {
        // TODO: Use a more appropriate data type for storing order
        let lo: Double = orderForID(pos.previousID) ?? 1.0
        let hi: Double = orderForID(pos.nextID) ?? 9.0
        return RelationValue(lo + ((hi - lo) / 2.0))
    }

    // XXX
    private func orderForID(id: RelationValue?) -> Double? {
        if let id = id {
            if let index = indexForID(id) {
                let row = rows[index].value
                return row[orderAttr].get()
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
    
    /// Returns the index of the item with the given ID, relative to the sorted rows array.
    public func indexForID(id: RelationValue) -> Int? {
        return rows.indexOf({ $0.value[idAttr] == id })
    }
}
