// Minimal native-style SwiftSignalKit, intentionally without library evolution.
public enum NoError: Error {}
public protocol Disposable: AnyObject { func dispose() }
private final class EmptyDisposable: Disposable { func dispose() {} }
public final class Signal<Value, ErrorType> {
    private let value: Value
    public init(_ value: Value) { self.value = value }
    public func start(next: ((Value) -> Void)!, error: ((ErrorType) -> Void)!, completed: (() -> Void)!) -> any Disposable {
        next?(value)
        return EmptyDisposable()
    }
}
