//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Darwin


/// A PRNG that produces consistent output on each run. Obviously, don't use this for anything
/// where randomness is relevant to security. Intended for pseudorandom test cases that can be
/// replicated on each run.
public struct ConsistentPRNG {
    fileprivate var state: [UInt16] = Array(repeating: 0, count: 3)
    
    public mutating func next() -> Int {
        return nrand48(&state)
    }
    
    public mutating func next(_ limit: Int) -> Int {
        return next() % limit
    }
    
    var max: Int {
        return 0x7fffffff
    }
}
