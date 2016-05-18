
/// Silly placeholder until we figure out what the error type should actually look like.
public typealias RelationError = ErrorType

public struct RelationChange {
    public var added: Relation?
    public var removed: Relation?
}

public protocol Relation: CustomStringConvertible, PlaygroundMonospace {
    var scheme: Scheme { get }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>>
    func contains(row: Row) -> Result<Bool, RelationError>
    
    func forEach(@noescape f: (Row, Void -> Void) -> Void) -> Result<Void, RelationError>
    
    mutating func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError>
    
    /// Add an observer function which is called when the content of the Relation
    /// changes. The return value is a function which removes the observation when
    /// invoked. The caller can use that function to cancel the observation when
    /// it no longer needs it.
    func addChangeObserver(f: RelationChange -> Void) -> (Void -> Void)
    
    func union(other: Relation) -> Relation
    func intersection(other: Relation) -> Relation
    func difference(other: Relation) -> Relation
    
    func join(other: Relation) -> Relation
    func equijoin(other: Relation, matching: [Attribute: Attribute]) -> Relation
    func thetajoin(other: Relation, query: SelectExpression) -> Relation
    func split(query: SelectExpression) -> (Relation, Relation)
    func divide(other: Relation) -> Relation
    func max(attribute: Attribute) -> Relation
    
    func select(rowToFind: Row) -> Relation
    func select(query: SelectExpression) -> Relation
    
    /// Return a new Relation that is this Relation with the given update applied to it.
    func withUpdate(query: SelectExpression, newValues: Row) -> Relation
    
    /// The same as the two-parameter withUpdate, but it updates all rows.
    func withUpdate(newValues: Row) -> Relation
    
    func renameAttributes(renames: [Attribute: Attribute]) -> Relation
}

extension Relation {
    public func forEach(@noescape f: (Row, Void -> Void) -> Void) -> Result<Void, RelationError>{
        for row in rows() {
            var stop = false
            
            switch row {
            case .Ok(let row):
                f(row, { stop = true })
            case .Err(let e):
                return .Err(e)
            }
            
            if stop {
                break
            }
        }
        return .Ok()
    }
    
    public func union(other: Relation) -> Relation {
        return UnionRelation(a: self, b: other)
    }
    
    public func intersection(other: Relation) -> Relation {
        return IntersectionRelation(a: self, b: other)
    }
    
    public func difference(other: Relation) -> Relation {
        return DifferenceRelation(a: self, b: other)
    }
    
    public func project(scheme: Scheme) -> Relation {
        return ProjectRelation(relation: self, scheme: scheme)
    }
    
    public func join(other: Relation) -> Relation {
        let intersectedScheme = Scheme(attributes: self.scheme.attributes.intersect(other.scheme.attributes))
        let matching = Dictionary(intersectedScheme.attributes.map({ ($0, $0) }))
        return equijoin(other, matching: matching)
    }
    
    public func equijoin(other: Relation, matching: [Attribute: Attribute]) -> Relation {
        return EquijoinRelation(a: self, b: other, matching: matching)
    }
    
    public func thetajoin(other: Relation, query: SelectExpression) -> Relation {
        return self.join(other).select(query)
    }
    
    public func split(query: SelectExpression) -> (Relation, Relation) {
        let matching = select(query)
        let notmatching = difference(matching)
        return (matching, notmatching)
    }
    
    public func divide(other: Relation) -> Relation {
        let resultingScheme = Scheme(attributes: self.scheme.attributes.subtract(other.scheme.attributes))
        let allCombinations = self.project(resultingScheme).join(other)
        let subtracted = allCombinations.difference(self)
        let projected = subtracted.project(resultingScheme)
        let result = self.project(resultingScheme).difference(projected)
        return result
    }
    
    public func max(attribute: Attribute) -> Relation {
        return MaxRelation(relation: self, attribute: attribute)
    }
}

extension Relation {
    public func select(rowToFind: Row) -> Relation {
        let rowScheme = Set(rowToFind.values.map({ $0.0 }))
        precondition(rowScheme.isSubsetOf(scheme.attributes))
        return select(SelectExpressionFromRow(rowToFind))
    }
    
    public func select(query: SelectExpression) -> Relation {
        return SelectRelation(relation: self, query: query)
    }
}

extension Relation {
    public func renameAttributes(renames: [Attribute: Attribute]) -> Relation {
        return RenameRelation(relation: self, renames: renames)
    }
    
    public func renamePrime() -> Relation {
        let renames = Dictionary(scheme.attributes.map({ ($0, Attribute($0.name + "'")) }))
        return renameAttributes(renames)
    }
}

extension Relation {
    public func withUpdate(query: SelectExpression, newValues: Row) -> Relation {
        // Pick out the rows which will be updated, and update them.
        let toUpdate = self.select(query)
        let updatedValues = toUpdate.withUpdate(newValues)
        
        // Pick out the rows not selected for the update.
        let nonUpdated = self.select(*!query)
        
        // The result is the union of the updated values and the rows not selected.
        return nonUpdated.union(updatedValues)
    }
    
    public func withUpdate(newValues: Row) -> Relation {
        return UpdateRelation(relation: self, newValues: newValues)
    }
}

extension Relation {
    public var isEmpty: Result<Bool, RelationError> {
        switch rows().next() {
        case .None: return .Ok(true)
        case .Some(.Ok): return .Ok(false)
        case .Some(.Err(let e)): return .Err(e)
        }
    }
}

extension Relation {
    public var description: String {
        let columns = scheme.attributes.sort()
        let rows = self.rows().map({ row in
            columns.map({ (col: Attribute) -> String in
                switch row.map({ $0[col] }) {
                case .Ok(let value):
                    return String(value)
                case .Err(let err):
                    return "Err(\(err))"
                }
            })
        })
        
        let all = ([columns.map({ $0.name })] + rows)
        let lengths = all.map({ $0.map({ $0.characters.count }) })
        let columnLengths = (0 ..< columns.count).map({ index in
            return lengths.map({ $0[index] }).reduce(0, combine: Swift.max)
        })
        let padded = all.map({ zip(columnLengths, $0).map({ $1.pad(to: $0, with: " ") }) })
        let joined = padded.map({ $0.joinWithSeparator("  ") })
        return joined.joinWithSeparator("\n")
    }
}

extension Relation {
    func addWeakChangeObserver<T: AnyObject>(target: T, method: T -> RelationChange -> Void) {
        var remove: (Void -> Void)? = nil
        
        remove = self.addChangeObserver({ [weak target] in
            if let target = target {
                method(target)($0)
            } else {
                guard let remove = remove else { preconditionFailure("Change observer fired but remove function was never set!") }
                remove()
            }
        })
    }
    
    func addWeakChangeObserver<T: AnyObject>(target: T, call: (T, RelationChange) -> Void) {
        addWeakChangeObserver(target, method: { obj in { change in call(obj, change) } })
    }
}
