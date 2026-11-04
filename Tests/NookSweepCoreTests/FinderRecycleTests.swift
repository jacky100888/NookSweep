import CoreServices
import Foundation
import Testing
@testable import NookSweepCore

@Test func finderRecycleSendsOnlyTheSelectedURLAndResolvesTheReturnedItem() async throws {
    let source = URL(fileURLWithPath: "/Applications/Quote\" and slash\\\n測試.app")
    let destination = URL(fileURLWithPath: "/Users/example/.Trash/Renamed app.app")
    let actual = try await recycleApplicationWithFinder(source) { event in
        #expect(event.eventClass == AEEventClass(kAECoreSuite))
        let reply = NSAppleEventDescriptor.record()
        if event.eventID == AEEventID(kAEDelete) {
            #expect(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.fileURLValue?.path == source.path)
            reply.setDescriptor(NSAppleEventDescriptor(string: "已搬移項目的參照"), forKeyword: AEKeyword(keyDirectObject))
        } else {
            #expect(event.eventID == AEEventID(kAEGetData))
            let property = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
            #expect(property?.descriptorType == DescType(typeObjectSpecifier))
            #expect(property?.forKeyword(AEKeyword(keyAEContainer))?.stringValue == "已搬移項目的參照")
            #expect(property?.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue == OSType(pURL))
            reply.setDescriptor(NSAppleEventDescriptor(string: destination.absoluteString), forKeyword: AEKeyword(keyDirectObject))
        }
        return reply
    }
    #expect(actual == destination)
}

@Test func finderRecyclePreservesCancellationAutomationAndFilePermissionErrors() async {
    for code in [-128, -1743, -5000] {
        do {
            _ = try await recycleApplicationWithFinder(URL(fileURLWithPath: "/Applications/Example.app")) { _ in
                let reply = NSAppleEventDescriptor.record()
                reply.setDescriptor(NSAppleEventDescriptor(int32: Int32(code)), forKeyword: AEKeyword(keyErrorNumber))
                reply.setDescriptor(NSAppleEventDescriptor(string: "系統拒絕測試"), forKeyword: AEKeyword(keyErrorString))
                return reply
            }
            Issue.record("Finder 拒絕或取消時不得回報成功")
        } catch {
            #expect((error as NSError).domain == NSOSStatusErrorDomain)
            #expect((error as NSError).code == code)
            #expect(error.localizedDescription == "系統拒絕測試")
        }
    }
}

@Test func finderRecycleRejectsMissingResultsAndNonFileDestinations() async {
    for value in [nil, "https://example.com/not-trash"] as [String?] {
        do {
            _ = try await recycleApplicationWithFinder(URL(fileURLWithPath: "/Applications/Example.app")) { event in
                let reply = NSAppleEventDescriptor.record()
                if event.eventID == AEEventID(kAEDelete) {
                    if value != nil { reply.setDescriptor(NSAppleEventDescriptor(string: "參照"), forKeyword: AEKeyword(keyDirectObject)) }
                } else if let value {
                    reply.setDescriptor(NSAppleEventDescriptor(string: value), forKeyword: AEKeyword(keyDirectObject))
                }
                return reply
            }
            Issue.record("缺少有效本機目的地時不得回報成功")
        } catch { #expect(error.localizedDescription.contains("Finder 未回傳垃圾桶位置")) }
    }
}
