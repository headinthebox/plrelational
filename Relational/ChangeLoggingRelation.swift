
public enum ChangeLoggingRelationChange {
    case Union(Relation)
    case Select(SelectExpression)
    case Update(SelectExpression, Row)
}

public struct ChangeLoggingRelationSnapshot {
    var savedLog: [ChangeLoggingRelationChange]
}

public class ChangeLoggingRelation<UnderlyingRelation: Relation> {
    let underlyingRelation: UnderlyingRelation
    
    var log: [ChangeLoggingRelationChange] = []
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    public init(underlyingRelation: UnderlyingRelation) {
        self.underlyingRelation = underlyingRelation
    }
    
    public func add(row: Row) {
        let relation = ConcreteRelation(row)
        log.append(.Union(relation))
        notifyChangeObservers(RelationChange(added: relation, removed: nil))
    }
    
    public func delete(query: SelectExpression) -> Result<Void, RelationError> {
        return computeFinalRelation().map({ finalRelation in
            let toDelete = finalRelation.select(query)
            log.append(.Select(*!query))
            notifyChangeObservers(RelationChange(added: nil, removed: toDelete))
        })
    }
    
    public func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        return computeFinalRelation().map({ currentState in
            let removed = currentState.select(query)
            let added = removed.withUpdate(newValues)
            
            log.append(.Update(query, newValues))
            notifyChangeObservers(RelationChange(added: added, removed: removed))
        })
    }
}

extension ChangeLoggingRelation: Relation, RelationDefaultChangeObserverImplementation {
    public var scheme: Scheme {
        return underlyingRelation.scheme
    }
    
    public func rows() -> AnyGenerator<Result<Row, RelationError>> {
        switch computeFinalRelation() {
        case .Ok(let relation):
            return relation.rows()
        case .Err(let err):
            return AnyGenerator(CollectionOfOne(Result.Err(err)).generate())
        }
    }
    
    public func contains(row: Row) -> Result<Bool, RelationError> {
        return computeFinalRelation().then({ $0.contains(row) })
    }
    
    internal func computeFinalRelation() -> Result<Relation, RelationError> {
        var addedRows = ConcreteRelation(scheme: scheme, values: [], defaultSort: nil)
        var removedRows = ConcreteRelation(scheme: scheme, values: [], defaultSort: nil)
        
        for change in log {
            switch change {
            case .Union(let relation):
                for row in relation.rows() {
                    switch row {
                    case .Ok(let row):
                        addedRows.add(row)
                        removedRows.delete(row)
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            case .Select(let query):
                addedRows.delete(*!query)
                for row in underlyingRelation.select(*!query).rows() {
                    switch row {
                    case .Ok(let row):
                        removedRows.add(row)
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            case .Update(let query, let newValues):
                addedRows.update(query, newValues: newValues)
                for toUpdate in underlyingRelation.select(query).difference(removedRows).rows() {
                    switch toUpdate {
                    case .Ok(let row):
                        addedRows.add(Row(values: row.values + newValues.values))
                        removedRows.add(row)
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            }
        }
        
        return .Ok(underlyingRelation.difference(removedRows).union(addedRows))
    }
    
    static func computeChangeFromLog<Log: SequenceType where Log.Generator.Element == ChangeLoggingRelationChange>(log: Log, underlyingRelation: Relation) -> RelationChange {
        var currentAdd: Relation = ConcreteRelation(scheme: underlyingRelation.scheme)
        var currentRemove: Relation = ConcreteRelation(scheme: underlyingRelation.scheme)
        
        for change in log {
            switch change {
            case .Union(let relation):
                currentAdd = currentAdd.union(relation.difference(currentRemove))
                currentRemove = currentRemove.difference(relation)
            case .Select(let query):
                currentAdd = currentAdd.select(query)
                currentRemove = currentRemove.union(underlyingRelation.select(*!query))
            case .Update(let query, let newValues):
                currentAdd = currentAdd.withUpdate(query, newValues: newValues)
                currentAdd = currentAdd.union(underlyingRelation.select(query).difference(currentRemove).withUpdate(newValues))
                currentRemove = currentRemove.union(underlyingRelation.select(query))
            }
        }
        
        return RelationChange(added: currentAdd, removed: currentRemove)
    }
}

extension ChangeLoggingRelation where UnderlyingRelation: SQLiteTableRelation {
    public func save() -> Result<Void, RelationError> {
        // TODO: transactions!
        let change = ChangeLoggingRelation.computeChangeFromLog(self.log, underlyingRelation: self.underlyingRelation)
        if let removed = change.removed {
            for row in removed.rows() {
                switch row {
                case .Ok(let row):
                    if let err = underlyingRelation.delete(SelectExpressionFromRow(row)).err {
                        return .Err(err)
                    }
                case .Err(let err):
                    return .Err(err)
                }
            }
        }
        
        if let added = change.added {
            for row in added.rows() {
                switch row {
                case .Ok(let row):
                    if let err = underlyingRelation.add(row).err {
                        return .Err(err)
                    }
                case .Err(let err):
                    return .Err(err)
                }
                
            }
        }
        
        return .Ok()
    }
}

extension ChangeLoggingRelation {
    public func takeSnapshot() -> ChangeLoggingRelationSnapshot {
        return ChangeLoggingRelationSnapshot(savedLog: self.log)
    }
    
    public func restoreSnapshot(snapshot: ChangeLoggingRelationSnapshot, notifyObservers: Bool = true) {
        self.log = snapshot.savedLog
        if notifyObservers {
            // XXX TODO: we need to provide the actual changes here!
            notifyChangeObservers(RelationChange(added: nil, removed: nil))
        }
    }
    
    public func restoreEmptySnapshot(notifyObservers notifyObservers: Bool = true) {
        self.log = []
        if notifyObservers {
            // XXX TODO: we need to provide the actual changes here!
            notifyChangeObservers(RelationChange(added: nil, removed: nil))
        }
    }
}
