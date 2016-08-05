//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import libRelational

extension Relation {
    /// Returns an AsyncReadableProperty that gets its value from this relation.
    public func asyncProperty<S: SignalType>(relationToSignal: Relation -> S) -> AsyncReadableProperty<S.Value> {
        return AsyncReadableProperty(relationToSignal(self).signal)
    }
}

private class RelationAsyncReadWriteProperty<T>: AsyncReadWriteProperty<T> {
    private let config: RelationMutationConfig<T>
    private var mutableValue: T?
    private var removal: ObserverRemoval!
    private var before: ChangeLoggingDatabaseSnapshot?

    init(config: RelationMutationConfig<T>, signal: Signal<T>) {
        self.config = config
        
        super.init(signal: signal)
        
        self.removal = signal.observe({ newValue, _ in
            self.mutableValue = newValue
        })
    }
    
    deinit {
        removal()
    }
    
    private override func getValue() -> T? {
        return mutableValue
    }
    
    private override func setValue(value: T, _ metadata: ChangeMetadata) {
        if before == nil {
            before = config.snapshot()
        }
        
        // Note: We don't set `mutableValue` here; instead we wait to receive the change from the
        // relation in our change observer and then update `mutableValue` there
        if metadata.transient {
            config.update(newValue: value)
        } else {
            config.commit(before: before!, newValue: value)
            before = nil
        }
    }
}

extension Relation {
    /// Returns an AsyncReadWriteProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func asyncProperty<S: SignalType>(config: RelationMutationConfig<S.Value>, _ relationToSignal: Relation -> S) -> AsyncReadWriteProperty<S.Value> {
        return RelationAsyncReadWriteProperty(config: config, signal: relationToSignal(self).signal)
    }
}
