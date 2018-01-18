//
//  RxProperty.swift
//  RxProperty
//
//  Created by George Kaimakas on 04/01/2018.
//

import Foundation
import RxSwift



internal protocol BahaviorSubjectWrapper: class {

}

public protocol RxPropertyProtocol: class, ObservableConvertibleType {
    /// The current value of the property.
    var value: E { get }
}

public final class RxProperty<Value>: RxPropertyProtocol {
    private let _value: () -> Value
    private let _observable: Observable<Value>

    public var value: Value {
        return _value()
    }

    public func asObservable() -> Observable<Value> {
        return _observable
    }

    public init(value: Value) {
        _value = { value }
        _observable = Observable.just(value)
    }

    public init(initial: Value, then values: Observable<Value>) {
        let subject = BehaviorSubject<Value>(value: initial)

        values
            .materialize()
            .filter {
                switch $0 {
                case .next(let element): return true
                default: return false
                }
            }
            .map { $0.element }
            .filter { $0 != nil }
            .map { $0! }
            .subscribe(subject.on)

        _value = { try! subject.value() }
        _observable = subject.asObservable()
    }

//    internal init(unsafeObservable: Observable<Value>) {
//        let subject = BehaviorSubject<Value>.in
//        _value = { 0 }
//    }

}
