import SwiftSignalKit

@_silgen_name("TGExtraFixtureMakeDisposable")
func makeFixtureDisposable() -> Disposable

@_silgen_name("TGExtraFixtureDisposalCount")
func fixtureDisposalCount() -> Int

@main
struct DisposableABITests {
    static func main() {
        let disposables = (0..<3).map { _ in makeFixtureDisposable() }
        disposables.forEach { $0.dispose() }
        precondition(fixtureDisposalCount() == 3)
        disposables.forEach { $0.dispose() }
        precondition(fixtureDisposalCount() == 3)
        print("SwiftSignalKit Disposable ABI: runtime dispatch passed")
    }
}
