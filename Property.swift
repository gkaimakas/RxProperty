//
//  Property.swift
//  RxProperty
//
//  Created by George Kaimakas on 03/01/2018.
//

import Foundation
import RxSwift


/// Represents a property that allows observation of its changes.
///
/// Only classes can conform to this protocol, because having a signal
/// for changes over time implies the origin must have a unique identity.
public protocol PropertyProtocol: class, ObservableConvertibleType {
    /// The current value of the property.
    var value: E { get }
}

/// Represents an observable property that can be mutated directly.
public protocol MutablePropertyProtocol: PropertyProtocol {
    /// The current value of the property.
    var value: E { get set }
}

public final class MutableProperty<Value>: MutablePropertyProtocol {
    public typealias E = Value

    private let _subject: BehaviorSubject<Value>
    private let _observable: Observable<Value>

    public var value: Value {
        get {
            return try! _subject.value()
        }
        set {
            _subject.on(.next(newValue))
        }
    }

    public init( _ initialValue: Value) {
        _subject = BehaviorSubject(value: initialValue)
        _observable = _subject.asObservable()
    }

    public func asObservable() -> Observable<Value> {
        return _observable
    }
}


public final class Property<Value>: PropertyProtocol {
    public typealias E = Value

    private let _value: () -> E
    private let _observable: Observable<E>

    /// The current value of the property.
    public var value: E {
        return _value()
    }

    /// Initializes a constant property.
    ///
    /// - parameters:
    ///   - property: A value of the constant property.
    public init(value: E) {
        _value = { value }
        _observable = Observable.just(value)
    }

    /// Initializes an existential property which wraps the given property.
    ///
    /// - note: The resulting property retains the given property.
    ///
    /// - parameters:
    ///   - property: A property to be wrapped.
    public init<P: PropertyProtocol>(capturing property: P) where P.E == E {
        _value = { property.value }
        _observable = property.asObservable()
    }

    /// Initializes a composed property which reflects the given property.
    ///
    /// - note: The resulting property does not retain the given property.
    ///
    /// - parameters:
    ///   - property: A property to be wrapped.
    public convenience init<P: PropertyProtocol>(_ property: P) where P.E == E {
        self.init(unsafeObservable: property.asObservable())
    }

    /// Initializes a composed property that first takes on `initial`, then each
    /// value sent on a signal created by `producer`.
    ///
    /// - parameters:
    ///   - initial: Starting value for the property.
    ///   - values: A producer that will start immediately and send values to
    ///             the property.
    public convenience init(initial: Value, then values: Observable<Value>) {
        self.init(unsafeObservable: Observable<Value>
            .just(initial)
            .concat(values))
    }

    fileprivate init(unsafeObservable: Observable<Value>) {

        // The ownership graph:
        //
        // ------------     weak  -----------    strong ------------------
        // | Upstream | ~~~~~~~~> |   Box   | <======== | SignalProducer | <=== strong
        // ------------           -----------       //  ------------------    \\
        //  \\                                     //                          \\
        //   \\   ------------ weak  ----------- <==                          ------------
        //    ==> | Observer | ~~~~> |  Relay  | <=========================== | Property |
        // strong ------------       -----------                       strong ------------

        let box = PropertyBox<Value?>(nil)

        let subject = BehaviorSubject<Wrapper<E>>(value: .empty)
        let (relay, observer) = (subject.asObservable(), subject.asObserver())

        // A composed property tracks its active consumers through its relay signal, and
        // interrupts `unsafeProducer` if the relay signal terminates.
        let disposable = SerialDisposable()

        disposable.disposable = unsafeObservable

            .subscribe (onNext:{ [weak box] event in

                guard let box = box else {
                    // Just forward the event, since no one owns the box or IOW no demand
                    // for a cached latest value.
                    return observer.onNext(.value(event))
                }

                box.begin { storage in
                    storage.modify { value in
                        value = event
                    }
                    observer.onNext(.value(event))
                }
        })

        // Verify that an initial is sent. This is friendlier than deadlocking
        // in the event that one isn't.
        guard box.value != nil else {
            fatalError("The producer promised to send at least one value. Received none.")
        }

        _value = { box.value! }
        _observable = relay
            .filter {
                switch $0 {
                case .value(_): return true
                case .empty: return false
                }
            }
            .map {
                switch $0 {
                case .value(let element): return element
                case .empty: fatalError()
                }
        }

    }

    public func asObservable() -> Observable<E> {
        return _observable
    }
}

internal enum Wrapper<E> {
    case value(E)
    case empty
}

internal struct PropertyStorage<Value> {
    private unowned let box: PropertyBox<Value>

    var value: Value {
        return box._value
    }

    func modify<Result>(_ action: (inout Value) throws -> Result) rethrows -> Result {
        guard !box.isModifying else { fatalError("Nested modifications violate exclusivity of access.") }
        box.isModifying = true
        defer { box.isModifying = false }
        return try action(&box._value)
    }

    fileprivate init(_ box: PropertyBox<Value>) {
        self.box = box
    }
}

/// A reference counted box which holds a recursive lock and a value storage.
///
/// The requirement of a `Value?` storage from composed properties prevents further
/// implementation sharing with `MutableProperty`.
private final class PropertyBox<Value> {

    private let lock: PthreadLock
    fileprivate var _value: Value
    fileprivate var isModifying = false

    internal var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    init(_ value: Value) {
        _value = value
        lock = PthreadLock(recursive: true)
    }

    func withValue<Result>(_ action: (Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try action(_value)
    }

    func begin<Result>(_ action: (PropertyStorage<Value>) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try action(PropertyStorage(self))
    }
}

internal final class PthreadLock {
    private let _lock: UnsafeMutablePointer<pthread_mutex_t>

    init(recursive: Bool = false) {
        _lock = .allocate(capacity: 1)
        _lock.initialize(to: pthread_mutex_t())

        let attr = UnsafeMutablePointer<pthread_mutexattr_t>.allocate(capacity: 1)
        attr.initialize(to: pthread_mutexattr_t())
        pthread_mutexattr_init(attr)

        defer {
            pthread_mutexattr_destroy(attr)
            attr.deinitialize()
            attr.deallocate(capacity: 1)
        }

        // Darwin pthread for 32-bit ARM somehow returns `EAGAIN` when
        // using `trylock` on a `PTHREAD_MUTEX_ERRORCHECK` mutex.
        #if DEBUG && !arch(arm)
            pthread_mutexattr_settype(attr, Int32(recursive ? PTHREAD_MUTEX_RECURSIVE : PTHREAD_MUTEX_ERRORCHECK))
        #else
            pthread_mutexattr_settype(attr, Int32(recursive ? PTHREAD_MUTEX_RECURSIVE : PTHREAD_MUTEX_NORMAL))
        #endif

        let status = pthread_mutex_init(_lock, attr)
        assert(status == 0, "Unexpected pthread mutex error code: \(status)")
    }

    func lock() {
        let status = pthread_mutex_lock(_lock)
        assert(status == 0, "Unexpected pthread mutex error code: \(status)")
    }

    func unlock() {
        let status = pthread_mutex_unlock(_lock)
        assert(status == 0, "Unexpected pthread mutex error code: \(status)")
    }

    func `try`() -> Bool {
        let status = pthread_mutex_trylock(_lock)
        switch status {
        case 0:
            return true
        case EBUSY:
            return false
        default:
            assertionFailure("Unexpected pthread mutex error code: \(status)")
            return false
        }
    }

    deinit {
        let status = pthread_mutex_destroy(_lock)
        assert(status == 0, "Unexpected pthread mutex error code: \(status)")

        _lock.deinitialize()
        _lock.deallocate(capacity: 1)
    }
}
