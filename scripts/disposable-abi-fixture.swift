// Build without library evolution, as in Telegram's SwiftSignalKit binary.
public protocol Disposable: AnyObject { func dispose() }

private var disposalCount = 0
private final class FixtureDisposable: Disposable {
    private var disposed = false
    func dispose() {
        if !disposed { disposed = true; disposalCount += 1 }
    }
}

@_silgen_name("TGExtraFixtureMakeDisposable")
public func makeFixtureDisposable() -> Disposable { FixtureDisposable() }

@_silgen_name("TGExtraFixtureDisposalCount")
public func fixtureDisposalCount() -> Int { disposalCount }
