import Foundation

public struct SystemCPUReading: Sendable {
    public let fraction: Double
    public let cores: [Double]

    static func calculate(previous: [[UInt64]], current: [[UInt64]]) -> Self? {
        guard previous.count == current.count, !current.isEmpty else { return nil }
        var cores: [Double] = []
        var total: UInt64 = 0
        var active: UInt64 = 0
        for (old, new) in zip(previous, current) {
            guard old.count == 4, new.count == 4,
                  zip(old, new).allSatisfy({ $1 >= $0 }) else { return nil }
            let delta = zip(old, new).map { $1 - $0 }
            let sum = delta.reduce(0, +)
            guard sum > 0 else { return nil }
            let busy = sum - delta[2]
            cores.append(Double(busy) / Double(sum))
            total += sum
            active += busy
        }
        return Self(fraction: Double(active) / Double(total), cores: cores)
    }
}

public enum SystemMemoryPressure: String, Sendable {
    case normal = "正常"
    case warning = "壓力偏高"
    case critical = "壓力過高"
    case unknown = "無法取得壓力狀態"
}

public struct SystemMemoryReading: Sendable {
    public let used: UInt64
    public let total: UInt64
    public let pressure: SystemMemoryPressure
    public var fraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
}

public struct SystemDiskReading: Sendable {
    public let total: Int64
    public let available: Int64
    public var fraction: Double { total > 0 ? min(1, max(0, Double(total - available) / Double(total))) : 0 }
}

public struct SystemNetworkReading: Sendable {
    public let interface: String
    public let downloadPerSecond: Double?
    public let uploadPerSecond: Double?

    static func rate(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double? {
        guard elapsed.isFinite, elapsed > 0, current >= previous else { return nil }
        return Double(current - previous) / elapsed
    }
}

public struct SystemBatteryReading: Sendable {
    public let fraction: Double
    public let isCharging: Bool
    public let isPluggedIn: Bool
}

public struct SystemProcessReading: Identifiable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let residentBytes: UInt64
}

public struct SystemSnapshot: Sendable {
    public let sampledAt: Date
    public let uptime: TimeInterval
    public let thermalState: String
    public let cpu: SystemCPUReading?
    public let memory: SystemMemoryReading?
    public let disk: SystemDiskReading?
    public let network: SystemNetworkReading?
    public let battery: SystemBatteryReading?
    public let processes: [SystemProcessReading]
    public let unavailable: [String]
}
