
public protocol ValueProvider {
    func valueForRow(row: Row) -> Value
}

public protocol Comparator {
    func matches(a: Value, _ b: Value) -> Bool
}

extension Attribute: ValueProvider {
    public func valueForRow(row: Row) -> Value {
        return row[self]
    }
}

extension String: ValueProvider {
    public func valueForRow(row: Row) -> Value {
        return self
    }
}

public struct ComparisonTerm {
    var lhs: ValueProvider
    var op: Comparator
    var rhs: ValueProvider
    
    public init(_ lhs: ValueProvider, _ op: Comparator, _ rhs: ValueProvider) {
        self.lhs = lhs
        self.op = op
        self.rhs = rhs
    }
}

public struct EqualityComparator: Comparator {
    public init() {}
    
    public func matches(a: Value, _ b: Value) -> Bool {
        return a == b
    }
}

public struct LTComparator: Comparator {
    public init() {}
    
    public func matches(a: Value, _ b: Value) -> Bool {
        return a < b
    }
}

public struct AnyComparator: Comparator {
    var compare: (Value, Value) -> Bool
    
    public init(_ compare: (Value, Value) -> Bool) {
        self.compare = compare
    }
    
    public func matches(a: Value, _ b: Value) -> Bool {
        return compare(a, b)
    }
}
