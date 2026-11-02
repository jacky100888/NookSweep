import Darwin
import Foundation
import IOKit.ps
import SystemConfiguration

struct SystemNetworkCounters {
    let interface: String
    let received: UInt64
    let sent: UInt64
}

func systemNetworkCounters() -> SystemNetworkCounters? {
    let ipv4 = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
    let ipv6 = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv6" as CFString) as? [String: Any]
    let primary = (ipv4?["PrimaryInterface"] ?? ipv6?["PrimaryInterface"]) as? String
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let head else { return nil }
    defer { freeifaddrs(head) }
    var cursor: UnsafeMutablePointer<ifaddrs>? = head
    var fallback: SystemNetworkCounters?
    while let entry = cursor {
        defer { cursor = entry.pointee.ifa_next }
        let interface = entry.pointee
        guard interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
              let data = interface.ifa_data,
              interface.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING),
              interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
        let name = String(cString: interface.ifa_name)
        let values = data.assumingMemoryBound(to: if_data.self).pointee
        let counters = SystemNetworkCounters(interface: name,
            received: UInt64(values.ifi_ibytes), sent: UInt64(values.ifi_obytes))
        if name == primary { return counters }
        if fallback == nil, name.hasPrefix("en") { fallback = counters }
    }
    // shortcut: getifaddrs 的 32 位元計數器回捲時捨棄一次速率，若需長期精準流量再改用 64 位元路由統計。
    return fallback
}

func systemBatteryReading() -> SystemBatteryReading? {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for source in sources {
        guard let values = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
              values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let current = values[kIOPSCurrentCapacityKey] as? NSNumber,
              let maximum = values[kIOPSMaxCapacityKey] as? NSNumber,
              maximum.doubleValue > 0 else { continue }
        return SystemBatteryReading(fraction: min(1, max(0, current.doubleValue / maximum.doubleValue)),
            isCharging: values[kIOPSIsChargingKey] as? Bool ?? false,
            isPluggedIn: values[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
    }
    return nil
}

func systemProcesses() -> [SystemProcessReading] {
    let estimated = proc_listallpids(nil, 0)
    guard estimated > 0 else { return [] }
    var pids = [Int32](repeating: 0, count: Int(estimated) + 64)
    let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
    guard count > 0 else { return [] }
    var processes: [SystemProcessReading] = []
    for pid in pids.prefix(min(Int(count), pids.count)) where pid > 0 {
        var info = proc_taskinfo()
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size)) ==
                MemoryLayout<proc_taskinfo>.size, info.pti_resident_size > 0 else { continue }
        var name = [CChar](repeating: 0, count: 1024)
        let length = name.withUnsafeMutableBytes { proc_name(pid, $0.baseAddress, UInt32($0.count)) }
        guard length > 0 else { continue }
        let processName = name.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        processes.append(SystemProcessReading(pid: pid, name: processName, residentBytes: info.pti_resident_size))
    }
    return Array(processes.sorted { $0.residentBytes > $1.residentBytes }.prefix(6))
}
