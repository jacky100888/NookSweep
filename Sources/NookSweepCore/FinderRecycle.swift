import CoreServices
import Foundation

func recycleApplicationWithFinder(_ url: URL,
    send: @escaping @Sendable (NSAppleEventDescriptor) throws -> NSAppleEventDescriptor = sendFinderRecycleEvent
) async throws -> URL {
    try Task.checkCancellation()
    return try await Task.detached {
        let deletion = finderRecycleEvent(AEEventID(kAEDelete))
        deletion.setParam(NSAppleEventDescriptor(fileURL: url), forKeyword: AEKeyword(keyDirectObject))
        let reply = try send(deletion)
        try checkFinderRecycleError(reply)
        guard let reference = reply.forKeyword(AEKeyword(keyDirectObject)) else {
            throw CleanupError.refused("Finder 未回傳垃圾桶位置，請到 Finder 確認")
        }
        if let destination = reference.fileURLValue, destination.isFileURL { return destination }
        let property = NSAppleEventDescriptor.record()
        property.setDescriptor(NSAppleEventDescriptor(typeCode: OSType(typeProperty)), forKeyword: AEKeyword(keyAEDesiredClass))
        property.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        property.setDescriptor(NSAppleEventDescriptor(typeCode: OSType(pURL)), forKeyword: AEKeyword(keyAEKeyData))
        property.setDescriptor(reference, forKeyword: AEKeyword(keyAEContainer))
        guard let specifier = property.coerce(toDescriptorType: DescType(typeObjectSpecifier)) else {
            throw CleanupError.refused("Finder 未回傳垃圾桶位置，請到 Finder 確認")
        }
        let location = finderRecycleEvent(AEEventID(kAEGetData))
        location.setParam(specifier, forKeyword: AEKeyword(keyDirectObject))
        let result = try send(location)
        try checkFinderRecycleError(result)
        guard let value = result.forKeyword(AEKeyword(keyDirectObject))?.stringValue,
              let destination = URL(string: value), destination.isFileURL,
              destination.path.hasPrefix("/") else {
            throw CleanupError.refused("Finder 未回傳垃圾桶位置，請到 Finder 確認")
        }
        return destination
    }.value
}

private func finderRecycleEvent(_ eventID: AEEventID) -> NSAppleEventDescriptor {
    NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: eventID,
        targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder"),
        returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
}

private func checkFinderRecycleError(_ reply: NSAppleEventDescriptor) throws {
    if let code = reply.forKeyword(AEKeyword(keyErrorNumber))?.int32Value, code != 0 {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(code), userInfo: [
            NSLocalizedDescriptionKey: reply.forKeyword(AEKeyword(keyErrorString))?.stringValue ?? "Finder 無法完成系統搬移"
        ])
    }
}

private func sendFinderRecycleEvent(_ event: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
    try event.sendEvent(options: [.waitForReply, .alwaysInteract, .canSwitchLayer], timeout: TimeInterval(kNoTimeOut))
}
