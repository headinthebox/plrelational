//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public typealias ObserverRemoval = Void -> Void

public struct ChangeMetadata {
    public let transient: Bool
    
    public init(transient: Bool) {
        self.transient = transient
    }
}

public struct SignalObserver<T> {
    public let valueWillChange: () -> Void
    public let valueChanging: (change: T, metadata: ChangeMetadata) -> Void
    public let valueDidChange: () -> Void
    
    public init(
        valueWillChange: () -> Void,
        valueChanging: (change: T, metadata: ChangeMetadata) -> Void,
        valueDidChange: () -> Void)
    {
        self.valueWillChange = valueWillChange
        self.valueChanging = valueChanging
        self.valueDidChange = valueDidChange
    }
}

public class Signal<T> {
    public typealias Observer = SignalObserver<T>
    public typealias Notify = SignalObserver<T>

    private var observers: [UInt64: Observer] = [:]
    private var nextObserverID: UInt64 = 0
    
    private init() {
    }
    
    public static func pipe() -> (Signal, Notify) {
        let signal = Signal()
        let notify = SignalObserver(
            valueWillChange: signal.notifyWillChange,
            valueChanging: signal.notifyChanging,
            valueDidChange: signal.notifyDidChange
        )
        return (signal, notify)
    }

    public func observe(observer: Observer) -> ObserverRemoval {
        let id = nextObserverID
        nextObserverID += 1
        observers[id] = observer
        return { self.observers.removeValueForKey(id) }
    }

    /// Convenience form of `observe` that builds an Observer whose `valueWillChange` and `valueDidChange`
    /// handlers pass through to `notify`, but uses the given `valueChanging` handler.
    public func observe<U>(notify: SignalObserver<U>, _ valueChanging: (change: T, metadata: ChangeMetadata) -> Void) -> ObserverRemoval {
        return self.observe(SignalObserver(
            valueWillChange: notify.valueWillChange,
            valueChanging: valueChanging,
            valueDidChange: notify.valueDidChange
        ))
    }

    private func notifyWillChange() {
        for (_, observer) in observers {
            observer.valueWillChange()
        }
    }

    private func notifyChanging(change: T, metadata: ChangeMetadata) {
        for (_, observer) in observers {
            observer.valueChanging(change: change, metadata: metadata)
        }
    }

    private func notifyDidChange() {
        for (_, observer) in observers {
            observer.valueDidChange()
        }
    }

    // For testing purposes only.
    internal var observerCount: Int { return observers.count }
}
