//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public final class AsyncManager: PerThreadInstance {
    public typealias ObservationRemover = (Void) -> Void
    
    private var pendingActions: [Action] = []
    fileprivate var observedInfo: ObjectDictionary<AnyObject, ObservedRelationInfo> = [:]
    fileprivate var variableInfo: ObjectDictionary<AnyObject, [VariableEntry]> = [:]
    
    private let runloop: CFRunLoop
    private var runloopModes: [CFRunLoopMode] = [.commonModes]
    
    private var executionTimer: CFRunLoopTimer?
    
    public init() {
        self.runloop = CFRunLoopGetCurrent()
    }
    
    public enum State {
        /// Nothing is happening, no actionss have been registered.
        case idle
        
        /// Actions have been registered but are not yet running.
        case pending
        
        /// Actions are actively running.
        case running
        
        /// Actions have been run and didChange observers are being notified before returning back to idle.
        case stopping
    }
    
    private var stateObservers: [UInt64: (State) -> Void] = [:]
    private var stateObserversNextID: UInt64 = 0
    
    public var state: State = .idle {
        didSet {
            for (_, observer) in stateObservers {
                observer(state)
            }
        }
    }
    
    /// Add a runloop mode where this AsyncManager will run its non-async code.
    /// By default, it runs on the common runloop modes.
    public func addRunloopMode(_ mode: CFRunLoopMode) {
        runloopModes.append(mode)
    }
    
    public func addStateObserver(_ observer: @escaping (State) -> Void) -> ObservationRemover {
        let id = stateObserversNextID
        stateObserversNextID += 1
        
        stateObservers[id] = observer
        return { self.stateObservers.removeValue(forKey: id) }
    }
    
    public func registerUpdate(_ relation: Relation, query: SelectExpression, newValues: Row) {
        register(action: .update(relation, query, newValues))
    }
    
    public func registerAdd(_ relation: MutableRelation, row: Row) {
        register(action: .add(relation, row))
    }
    
    public func registerDelete(_ relation: MutableRelation, query: SelectExpression) {
        register(action: .delete(relation, query))
    }
    
    public func registerRestoreSnapshot(_ database: TransactionalDatabase, snapshot: ChangeLoggingDatabaseSnapshot) {
        register(action: .restoreSnapshot(database, snapshot))
    }
    
    public func registerQuery(_ relation: Relation, callback: DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>) {
        register(action: .query(relation, callback))
    }
    
    private func register(action: Action, atBeginning: Bool = false) {
        if atBeginning {
            pendingActions.insert(action, at: 0)
        } else {
            pendingActions.append(action)
        }
        
        switch action {
        case .add(let relation, let row):
            registerChange(relation, predicate: SelectExpressionFromRow(row))
        case .delete(let relation, let query):
            registerChange(relation, predicate: query)
        case .update(let relation, let query, _):
            registerChange(relation, predicate: query)
        case .restoreSnapshot(let database, _):
            for (_, relation) in database.relations {
                registerChange(relation, predicate: true)
            }
        case .query:
            break
        }
        
        if state == .idle {
            scheduleExecutionIfNeeded()
        }
    }
    
    /// Register an observer for a Relation. The observer will receive all changes made to the relation
    /// through the AsyncManager.
    public func observe(_ relation: Relation, observer: AsyncRelationChangeObserver, context: DispatchContext? = nil) -> ObservationRemover {
        guard let obj = asObject(relation) else { return {} }
        
        let info = infoForObservee(obj)
        let id = info.addObserver(observer, context: context ?? defaultObserverDispatchContext())
        
        return {
            info.observers[id] = nil
            if info.observers.isEmpty {
                self.observedInfo[obj] = nil
            }
        }
    }
    
    /// Register an observer for a Relation. When the Relation is changed through the AsyncManager,
    /// the observer receives the Relation's new contents.
    public func observe(_ relation: Relation, observer: AsyncRelationContentObserver, context: DispatchContext? = nil) -> ObservationRemover {
        guard let obj = asObject(relation) else { return {} }
        
        let info = infoForObservee(obj)
        let id = info.addObserver(observer, context: context ?? defaultObserverDispatchContext())
        
        return {
            info.observers[id] = nil
            if info.observers.isEmpty {
                self.observedInfo[obj] = nil
            }
        }
    }
    
    fileprivate func registerChange(_ relation: Relation, predicate: SelectExpression) {
        if state != .running {
            sendWillChange(relation, predicate: predicate)
            scheduleExecutionIfNeeded()
        }
    }
    
    fileprivate func sendWillChange(_ relation: Relation, predicate: SelectExpression) {
        QueryPlanner.visitRelationTree([(relation, ())], { relation, _, _ in
            guard let relationObject = asObject(relation), !(relation is IntermediateRelation) else { return }
            
            if let entries = variableInfo[relationObject] {
                for entry in entries {
                    if let filter = entry.filter, canProveInconsistent(predicate, filter) {
                        continue
                    }
                    var willChangeRelationObservers: [DispatchContextWrapped<AsyncRelationChangeObserver>] = []
                    var willChangeUpdateObservers: [DispatchContextWrapped<AsyncRelationContentObserver>] = []
                    entry.observedRelationInfo.observers.mutatingForEach({
                        if !$0.didSendWillChange {
                            $0.didSendWillChange = true
                            willChangeRelationObservers.appendNonNil($0.relationObserver)
                            willChangeUpdateObservers.appendNonNil($0.updateObserver)
                        }
                    })
                    for observer in willChangeRelationObservers {
                        observer.withWrapped({ $0.relationWillChange(entry.observedRelation) })
                    }
                    for observer in willChangeUpdateObservers {
                        observer.withWrapped({ $0.relationWillChange(entry.observedRelation) })
                    }
                }
            }
        })
    }
    
    fileprivate func sendWillChangeForAllPendingActions() {
        for action in pendingActions {
            switch action {
            case .add(let relation, let row):
                sendWillChange(relation, predicate: SelectExpressionFromRow(row))
            case .delete(let relation, let query):
                sendWillChange(relation, predicate: query)
            case .update(let relation, let query, _):
                sendWillChange(relation, predicate: query)
            case .restoreSnapshot(let database, _):
                for (_, relation) in database.relations {
                    registerChange(relation, predicate: true)
                }
            case .query:
                break
            }
        }
    }
    
    fileprivate func scheduleExecutionIfNeeded() {
        if executionTimer == nil {
            executionTimer = CFRunLoopTimerCreateWithHandler(nil, 0, 0, 0, 0, { _ in
                self.execute()
            })
            for mode in runloopModes {
                CFRunLoopAddTimer(runloop, executionTimer, mode)
            }
            state = .pending
        }
    }
    
    fileprivate func execute() {
        CFRunLoopTimerInvalidate(executionTimer)
        executionTimer = nil
        state = .running
        executeBody()
    }
    
    fileprivate func executeBody() {
        // Apply all pending actions asynchronously. Work is done in the background, with callbacks onto
        // this runloop for synchronization and notifying observers.
        let actions = pendingActions
        pendingActions = []
        
        let observedInfo = self.observedInfo
        
        // Run actions in the background.
        DispatchQueue.global().async(execute: {
            // Walk through all the observers. Observe changes on all relevant variables and update
            // observer derivatives with those changes as they come in. Also locate all
            // TransactionalDatabases referenced within so we can begin and end transactions.
            var databases: ObjectSet<TransactionalDatabase> = []
            var removals: [(Void) -> Void] = []
            for (_, info) in observedInfo {
                let derivative = info.derivative
                derivative.clearVariables()
                for variable in derivative.allVariables {
                    let removal = variable.addChangeObserver({
                        let copiedAddResult = $0.added.map(ConcreteRelation.copyRelation)
                        let copiedRemoveResult = $0.removed.map(ConcreteRelation.copyRelation)
                        
                        if let err = copiedAddResult?.err ?? copiedRemoveResult?.err {
                            fatalError("Error copying changes, don't know how to handle that yet: \(err)")
                        }
                        
                        let copiedChange = RelationChange(added: copiedAddResult?.ok, removed: copiedRemoveResult?.ok)
                        derivative.addChange(copiedChange, toVariable: variable)
                    })
                    removals.append(removal)
                    
                    if let transactionalRelation = variable as? TransactionalRelation,
                           let db = transactionalRelation.db {
                        databases.insert(db)
                    }
                }
            }
            
            // Wrap everything up in a transaction.
            // TODO: this doesn't really work when there's more than one database, even though we sort of
            // pretend like it does. Fix that? Explicitly limit it to one database?
            for db in databases {
                db.beginTransaction()
            }
            
            // Apply the actual updates to the relations. Ignore queries.
            for action in actions {
                let error: RelationError?
                switch action {
                case .update(let relation, let query, let newValues):
                    var mutableRelation = relation
                    let result = mutableRelation.update(query, newValues: newValues)
                    error = result.err
                case .add(let relation, let row):
                    let result = relation.add(row)
                    error = result.err
                case .delete(let relation, let query):
                    let result = relation.delete(query)
                    error = result.err
                case .restoreSnapshot(let database, let snapshot):
                    if databases.contains(database) {
                        // TODO: check for errors?
                        _ = database.endTransaction()
                        database.restoreSnapshot(snapshot)
                        database.beginTransaction()
                    } else {
                        database.restoreSnapshot(snapshot)
                    }
                    error = nil
                case .query:
                    error = nil
                }
                
                if let error = error {
                    fatalError("Don't know how to deal with update errors yet, got error \(error)")
                }
            }
            
            // And end the transaction.
            for db in databases {
                // TODO: check for errors?
                _ = db.endTransaction()
            }
            
            // All changes are done, so remove the observations registered above.
            for removal in removals {
                removal()
            }
            
            // Set up a QueryManager to run all the queries together.
            var queryManager = QueryManager()
            
            // We'll be doing a bunch of async work to notify observers. Use a dispatch group to figure out when it's all done.
            let doneGroup = DispatchGroup()
            
            // Go through all the observers and notify them.
            for (observedRelationObj, info) in observedInfo {
                let relation = observedRelationObj as! Relation
                let change = info.derivative.change
                
                let observersWithWillChange = info.observers.values.filter({ $0.didSendWillChange == true })
                let relationObservers = observersWithWillChange.flatMap({ $0.relationObserver })
                let updateObservers = observersWithWillChange.flatMap({ $0.updateObserver })
                
                if !relationObservers.isEmpty {
                    // If there are additions, then iterate over them and send them to the observer. Iteration is started in the
                    // original runloop, which ensures that the callbacks happen there too.
                    if let added = change.added {
                        doneGroup.enter()
                        queryManager.registerQuery(added, callback: DirectDispatchContext().wrap({ result in
                            switch result {
                            case .Ok(let rows) where rows.isEmpty:
                                doneGroup.leave()
                            case .Ok(let rows):
                                for observer in relationObservers {
                                    observer.withWrapped({ $0.relationAddedRows(relation, rows: rows) })
                                }
                            case .Err(let err):
                                for observer in relationObservers {
                                    observer.withWrapped({ $0.relationError(relation, error: err) })
                                }
                                doneGroup.leave()
                            }
                        }))
                    }
                    // Do the same if there are removals.
                    if let removed = change.removed {
                        doneGroup.enter()
                        queryManager.registerQuery(removed, callback: DirectDispatchContext().wrap({ result in
                            switch result {
                            case .Ok(let rows) where rows.isEmpty:
                                doneGroup.leave()
                            case .Ok(let rows):
                                for observer in relationObservers {
                                    observer.withWrapped({ $0.relationRemovedRows(relation, rows: rows) })
                                }
                            case .Err(let err):
                                for observer in relationObservers {
                                    observer.withWrapped({ $0.relationError(relation, error: err) })
                                }
                                doneGroup.leave()
                            }
                        }))
                    }
                }
                
                if !updateObservers.isEmpty {
                    doneGroup.enter()
                    queryManager.registerQuery(relation, callback: DirectDispatchContext().wrap({ result in
                        switch result {
                        case .Ok(let rows) where rows.isEmpty:
                            doneGroup.leave()
                        case .Ok(let rows):
                            for observer in updateObservers {
                                observer.withWrapped({ $0.relationNewContents(relation, rows: rows) })
                            }
                        case .Err(let err):
                            for observer in updateObservers {
                                observer.withWrapped({ $0.relationError(relation, error: err) })
                            }
                            doneGroup.leave()
                        }
                    }))
                }
            }
            
            // Make any requested queries.
            for action in actions {
                if case .query(let relation, let callback) = action {
                    doneGroup.enter()
                    queryManager.registerQuery(relation, callback: DirectDispatchContext().wrap({ result in
                        callback.withWrapped({
                            $0(result)
                            switch result {
                            case .Ok(let rows) where rows.isEmpty:
                                doneGroup.leave()
                            case .Err:
                                doneGroup.leave()
                            default:
                                break
                            }
                        })
                    }))
                }
            }
            
            queryManager.execute()
            
            // Wait until done. If there are no changes then this will execute immediately. Otherwise it will execute
            // when all the iteration above is complete.
            doneGroup.notify(queue: DispatchQueue.global(), execute: {
                self.runloop.async(inModes: self.runloopModes, {
                    // If new pending actions came in while we were doing our thing, then go back to the top
                    // and start over, performing those actions too.
                    if !self.pendingActions.isEmpty {
                        // All content observers currently being worked on need a didChange followed by a willChange
                        // so that they know they're getting new content, not additional content.
                        for (observedRelationObj, info) in observedInfo {
                            for (_, observer) in info.observers {
                                if observer.didSendWillChange {
                                    observer.updateObserver?.withWrapped({
                                        $0.relationDidChange(observedRelationObj as! Relation)
                                        $0.relationWillChange(observedRelationObj as! Relation)
                                    })
                                }
                            }
                        }
                        self.sendWillChangeForAllPendingActions()
                        self.executeBody()
                    } else {
                        // Otherwise, terminate the execution.
                        self.state = .stopping
                        
                        // Reset observers and send didChange to them.
                        var entriesWithWillChange: [(Relation, ObservedRelationInfo.ObserverEntry)] = []
                        for (observedRelationObj, info) in observedInfo {
                            info.derivative.clearVariables()
                            
                            let relation = observedRelationObj as! Relation
                            info.observers.mutatingForEach({
                                if $0.didSendWillChange {
                                    $0.didSendWillChange = false
                                    entriesWithWillChange.append((relation, $0))
                                }
                            })
                        }
                        
                        for (relation, entry) in entriesWithWillChange {
                            entry.relationObserver?.withWrapped({ $0.relationDidChange(relation) })
                            entry.updateObserver?.withWrapped({ $0.relationDidChange(relation) })
                        }
                        
                        // Suck out any pending actions that were queued up by didChange calls so we
                        // can add them back in after changing state.
                        let pendingActions = self.pendingActions
                        self.pendingActions.removeAll()
                        
                        self.state = .idle
                        
                        for action in pendingActions {
                            self.register(action: action, atBeginning: true)
                        }
                    }
                })
            })
        })
    }
    
    func defaultObserverDispatchContext() -> DispatchContext {
        return RunLoopDispatchContext(runloop: self.runloop,
                                      executeReentrantImmediately: true,
                                      modes: self.runloopModes)
    }
}

extension AsyncManager {
    fileprivate struct QueryManager {
        var pendingQueries: [(Relation, DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>)] = []
        
        mutating func registerQuery(_ relation: Relation, callback: DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>) {
            pendingQueries.append((relation, callback))
        }
        
        mutating func execute() {
            let planner = QueryPlanner(roots: pendingQueries)
            let runner = QueryRunner(planner: planner)
            
            while !runner.done {
                runner.pump()
            }
            
            if !runner.didError {
                for (_, callback) in pendingQueries {
                    callback.withWrapped({ $0(.Ok([])) })
                }
            }
        }
    }
}

extension AsyncManager {
    fileprivate enum Action {
        case update(Relation, SelectExpression, Row)
        case add(MutableRelation, Row)
        case delete(MutableRelation, SelectExpression)
        case restoreSnapshot(TransactionalDatabase, ChangeLoggingDatabaseSnapshot)
        case query(Relation, DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>)
    }
    
    fileprivate class ObservedRelationInfo {
        struct ObserverEntry {
            var relationObserver: DispatchContextWrapped<AsyncRelationChangeObserver>?
            var updateObserver: DispatchContextWrapped<AsyncRelationContentObserver>?
            var didSendWillChange: Bool
        }
        
        let derivative: RelationDerivative
        var observers: [UInt64: ObserverEntry] = [:]
        var currentObserverID: UInt64 = 0
        
        init(derivative: RelationDerivative) {
            self.derivative = derivative
        }
        
        func addObserver(_ observer: AsyncRelationChangeObserver, context: DispatchContext) -> UInt64 {
            currentObserverID += 1
            observers[currentObserverID] = ObserverEntry(relationObserver: DispatchContextWrapped(context: context, wrapped: observer), updateObserver: nil, didSendWillChange: false)
            return currentObserverID
        }
        
        func addObserver(_ observer: AsyncRelationContentObserver, context: DispatchContext) -> UInt64 {
            currentObserverID += 1
            observers[currentObserverID] = ObserverEntry(relationObserver: nil, updateObserver: DispatchContextWrapped(context: context, wrapped: observer), didSendWillChange: false)
            return currentObserverID
        }
    }
    
    fileprivate func infoForObservee(_ relationObject: AnyObject) -> ObservedRelationInfo {
        return observedInfo.getOrCreate(relationObject, defaultValue: makeInfoForObservee(relationObject as! Relation & AnyObject))
    }
    
    fileprivate func makeInfoForObservee(_ relation: Relation & AnyObject) -> ObservedRelationInfo {
        let derivative = RelationDifferentiator(relation: relation).computeDerivative()
        let info = ObservedRelationInfo(derivative: derivative)
        let filters = relationFilters(relation)
        for (variable, filter) in filters {
            let entry = VariableEntry(observedRelation: relation, observedRelationInfo: info, filter: filter)
            variableInfo[variable, defaultValue: []].append(entry)
        }
        
        let filtered = ObjectSet<AnyObject>(filters.map({ $0.0 }))
        for variable in derivative.allVariables where !filtered.contains(variable) {
            let entry = VariableEntry(observedRelation: relation, observedRelationInfo: info, filter: nil)
            variableInfo[variable, defaultValue: []].append(entry)
        }
        return info
    }
    
    fileprivate func relationFilters(_ relation: Relation & AnyObject) -> [(RelationDerivative.Variable, SelectExpression)] {
        guard let relation = relation as? IntermediateRelation else { return [] }
        
        var pending: ObjectSet<IntermediateRelation> = [relation]
        var result: ObjectDictionary<AnyObject, SelectExpression?> = [:]
        
        while !pending.isEmpty {
            let r = pending.removeFirst()
            for child in r.operands {
                switch child {
                case let child as IntermediateRelation:
                    pending.insert(child)
                case let child as RelationDerivative.Variable:
                    if case .select(let expression) = r.op {
                        if case .none = result[child] {
                            result[child] = expression
                        } else {
                            result[child] = nil
                        }
                    } else {
                        result[child] = nil
                    }
                default:
                    break
                }
            }
        }
        
        return result.filter({ $1 != nil }).map({ ($0 as! RelationDerivative.Variable, $1!) })
    }
}

extension AsyncManager {
    fileprivate struct VariableEntry {
        // TODO: weak reference?
        var observedRelation: Relation
        var observedRelationInfo: ObservedRelationInfo
        var filter: SelectExpression?
    }
    
    /// Try to (cheaply) see if a and b are inconsistent, i.e. can never both be true simultaneously.
    /// The function returns true if so. If it returns false, they may still be inconsistent, it
    /// just couldn't prove that. Right now the check is extremely basic.
    fileprivate func canProveInconsistent(_ a: SelectExpression, _ b: SelectExpression) -> Bool {
        // For now, just check to see if they're both equality with the same attribute
        // on one side, and different values on the other side.
        if let (attributeA, valueA) = equalityAttributeAndValue(a),
            let (attributeB, valueB) = equalityAttributeAndValue(b),
            attributeA == attributeB && valueA.relationValue != valueB.relationValue
        {
            return true
        }
        
        return false
    }
    
    fileprivate func equalityAttributeAndValue(_ expression: SelectExpression) -> (Attribute, SelectExpressionConstantValue)? {
        switch equalityOperands(expression) {
        case let .some(attr as Attribute, value as SelectExpressionConstantValue):
            return (attr, value)
        case let .some(value as SelectExpressionConstantValue, attr as Attribute):
            return (attr, value)
        default:
            return nil
        }
        
    }
    
    fileprivate func equalityOperands(_ expression: SelectExpression) -> (SelectExpression, SelectExpression)? {
        if let eq = expression as? SelectExpressionBinaryOperator, eq.op is EqualityComparator {
            return (eq.lhs, eq.rhs)
        } else {
            return nil
        }
    }
}

public extension MutableRelation {
    func asyncAdd(_ row: Row) {
        AsyncManager.currentInstance.registerAdd(self, row: row)
    }
    
    func asyncDelete(_ query: SelectExpression) {
        AsyncManager.currentInstance.registerDelete(self, query: query)
    }
}
