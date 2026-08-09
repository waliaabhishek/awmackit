import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let inputItem = context.inputItems.first as? NSExtensionItem
        let message = inputItem?.userInfo?[SFExtensionMessageKey]
        let response = NSExtensionItem()
        response.userInfo = [
            SFExtensionMessageKey: [
                "received": message != nil,
                "appScheme": "potliji-link",
            ]
        ]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
