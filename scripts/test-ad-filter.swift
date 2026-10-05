import Foundation

private final class AdMessageAttribute {}
private final class OrdinaryAttribute {}
private struct TestMessage { let text: String; let attributes: [Any] }
private enum TestContent { case message(message: TestMessage); case group(messages: [TestMessage]) }
private struct TestItem { let content: TestContent }
private class TestNode: NSObject { var item: TestItem?; init(_ item: TestItem?) { self.item = item } }
private final class InheritedNode: TestNode {}

@main
struct AdvertisementFilterTests {
    static func main() {
        let ordinary = TestMessage(text: "Inserzione: acquista su Amazon. AdMessageAttribute", attributes: [OrdinaryAttribute()])
        let ad = TestMessage(text: "Un annuncio", attributes: [AdMessageAttribute()])
        let node = InheritedNode(TestItem(content: .message(message: ordinary)))
        precondition(!TGExtraAdFilter.nodeIsAdvertisement(node), "Do not filter text or links")
        node.item = TestItem(content: .message(message: ad))
        precondition(TGExtraAdFilter.nodeIsAdvertisement(node), "Detect explicit ad attribute through superclass/optional/enum")
        node.item = TestItem(content: .group(messages: [ordinary, ad]))
        precondition(TGExtraAdFilter.nodeIsAdvertisement(node), "Detect grouped advertisements")
        node.item = TestItem(content: .message(message: ordinary))
        precondition(!TGExtraAdFilter.nodeIsAdvertisement(node), "Reused ordinary cell must not stay classified as an ad")
        node.item = nil
        precondition(!TGExtraAdFilter.nodeIsAdvertisement(node), "Empty cell must not be hidden")
        print("Advertisement filter: 5 tests passed")
    }
}
