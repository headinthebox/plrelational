//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

class QueryPlanner {
    private let rootRelation: Relation
    private var relationNodeIndexMap = ObjectMap<Int>()
    
    var nodes: [Node] = []
    var transactionalDatabases: ObjectSet<TransactionalDatabase> = []
    
    init(root: Relation) {
        self.rootRelation = root
        computeNodes()
    }
    
    var rootIndex: Int {
        // If the root is not an object then we'll only have one node. If it is, we can look it up.
        if rootRelation is AnyObject {
            return getOrCreateNodeIndex(rootRelation.underlyingRelationForQueryExecution)
        } else {
            return 0
        }
    }
    
    var initiatorIndexes: [Int] {
        return (nodes.indices).filter({
            switch nodes[$0].op {
            case .SQLiteTableScan, .ConcreteRows:
                return true
            default:
                return false
            }
        })
    }
    
    func initiatorRelation(initiator: QueryPlanner.Node) -> Relation {
        switch initiator.op {
        case .SQLiteTableScan(let relation):
            return relation
        default:
            fatalError("Node operation \(initiator.op) is not a known initiator operation")
        }
    }
    
    private func computeNodes() {
        // When visiting nodes, we get the underlying relations, so to catch the original root we have to do it here.
        // When iterating the children of a node, we get the originals, so we can call noteTransactionalDatabases
        // on those and it works. This is weird and should probably be revisited.
        noteTransactionalDatabases(rootRelation)
        visitRelationTree(rootRelation, { relation, isRoot in
            let children = relationChildren(relation)
            // Skip this whole thing for relations with no children. They'll have nodes created for them by their parents.
            // Except if the root node has no children, we still need to hit that one if anything is to happen at all.
            if children.count > 0 || isRoot {
                let nodeIndex = getOrCreateNodeIndex(relation)
                for (index, childRelation) in children.enumerate() {
                    noteTransactionalDatabases(childRelation)
                    let childNodeIndex = getOrCreateNodeIndex(childRelation.underlyingRelationForQueryExecution)
                    nodes[childNodeIndex].parentIndexes.append((nodeIndex, index))
                }
                nodes[nodeIndex].childCount = children.count
            }
        })
    }
    
    private func visitRelationTree(root: Relation, @noescape _ f: (Relation, isRoot: Bool) -> Void) {
        let visited = ObjectMap<Int>()
        var toVisit: [Relation] = [root]
        var isRoot = true
        var iterationCount = 0
        while let r = toVisit.popLast() {
            let realR = r.underlyingRelationForQueryExecution
            iterationCount += 1
            if let obj = realR as? AnyObject {
                let retrievedCount = visited.getOrCreate(obj, defaultValue: iterationCount)
                if retrievedCount != iterationCount {
                    continue
                }
            }
            f(realR, isRoot: isRoot)
            isRoot = false
            toVisit.appendContentsOf(relationChildren(realR))
        }
    }
    
    private func getOrCreateNodeIndex(r: Relation) -> Int {
        if let obj = r as? AnyObject {
            return relationNodeIndexMap.getOrCreate(obj, defaultValue: relationToNodeIndex(r))
        } else {
            return relationToNodeIndex(r)
        }
    }
    
    private func relationToNodeIndex(r: Relation) -> Int {
        let node = relationToNode(r)
        let index = nodes.count
        nodes.append(node)
        return index
    }
    
    private func relationToNode(r: Relation) -> Node {
        switch r {
        case let r as IntermediateRelation:
            return intermediateRelationToNode(r)
        case let r as ConcreteRelation:
            return Node(op: .ConcreteRows(r.values), parentIndexes: [])
        case let r as SQLiteRelation:
            return Node(op: .SQLiteTableScan(r), parentIndexes: [])
        default:
            fatalError("Don't know how to handle node type \(r.dynamicType)")
        }
    }
    
    private func relationChildren(r: Relation) -> [Relation] {
        switch r {
        case let r as IntermediateRelation:
            return r.operands
        default:
            return []
        }
    }
    
    private func intermediateRelationToNode(r: IntermediateRelation) -> Node {
        switch r.op {
        case .Union:
            return Node(op: .Union)
        case .Intersection:
            return Node(op: .Intersection)
        case .Difference:
            return Node(op: .Difference)
        case .Project(let scheme):
            return Node(op: .Project(scheme))
        case .Select(let expression):
            return Node(op: .Select(expression))
        case .MutableSelect(let expression):
            return Node(op: .Select(expression))
        case .Equijoin(let matching):
            return Node(op: .Equijoin(matching))
        case .Rename(let renames):
            return Node(op: .Rename(renames))
        case .Update(let newValues):
            return Node(op: .Update(newValues))
        case .Aggregate(let attribute, let initialValue, let aggregateFunction):
            return Node(op: .Aggregate(attribute, initialValue, aggregateFunction))
        case .Otherwise:
            return Node(op: .Otherwise)
        case .Unique(let attribute, let value):
            return Node(op: .Unique(attribute, value))
        }
    }
    
    private func noteTransactionalDatabases(r: Relation) {
        if let
            transactionalRelation = r as? TransactionalDatabase.TransactionalRelation,
            db = transactionalRelation.db {
            transactionalDatabases.insert(db)
        }
    }
}

extension QueryPlanner {
    struct Node {
        let op: Operation
        var childCount = 0
        var parentIndexes: [(nodeIndex: Int, childIndex: Int)]
        
        init(op: Operation, parentIndexes: [(nodeIndex: Int, childIndex: Int)] = []) {
            self.op = op
            self.parentIndexes = parentIndexes
        }
    }
    
    enum Operation {
        case SQLiteTableScan(SQLiteRelation)
        case ConcreteRows(Set<Row>)
        
        case Union
        case Intersection
        case Difference
        case Project(Scheme)
        case Select(SelectExpression)
        case Equijoin([Attribute: Attribute])
        case Rename([Attribute: Attribute])
        case Update(Row)
        case Aggregate(Attribute, RelationValue?, (RelationValue?, RelationValue) -> Result<RelationValue, RelationError>)
        
        case Otherwise
        case Unique(Attribute, RelationValue)
    }
}
