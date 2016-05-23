//
//  Binding.swift
//  Relational
//
//  Created by Chris Campbell on 5/3/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation

public protocol Binding {
    associatedtype Value
    associatedtype Change
    
    var value: Value { get }
    
    func addChangeObserver(observer: Change -> Void) -> (Void -> Void)
}

public protocol BidiBinding: Binding {
    func update(newValue: Value)
    func commit(newValue: Value)
}
