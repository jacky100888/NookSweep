import Darwin
import Foundation

public actor SystemSampler {
    private var previousCPU: [[UInt64]]?
    private var previousNetwork: SystemNetworkCounters?
    private var previousTime: TimeInterval?

    public init() { }

    public func reset() {
        previousCPU = nil
        previousNetwork = nil
        previousTime = nil
    }

    public func sample() -> SystemSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        let ticks = cpuTicks()
        let cpu = previousCPU.flatMap { old in ticks.flatMap { SystemCPUReading.calculate(previous: old, current: $0) } }
        previousCPU = ticks
        let counters = systemNetworkCounters()
        var network: SystemNetworkReading?
        if let counters {
            var download: Double?
            var upload: Double?
            if let previousNetwork, let previousTime, previousNetwork.interface == counters.interface {
                download = SystemNetworkReading.rate(previous: previousNetwork.received,
                    current: counters.received, elapsed: now - previousTime)
                upload = SystemNetworkReading.rate(previous: previousNetwork.sent,
                    current: counters.sent, elapsed: now - previousTime)
            }
            network = SystemNetworkReading(interface: counters.interface,
                downloadPerSecond: download, uploadPerSecond: upload)
        }
        previousNetwork = counters
        previousTime = now
        let memory = memoryReading()
        let disk = diskReading()
        var unavailable: [String] = []
        if ticks == nil { unavailable.append("CPU 使用率") }
        if memory == nil { unavailable.append("記憶體用量") }
        if disk == nil { unavailable.append("磁碟容量") }
        if counters == nil { unavailable.append("網路介面") }
        return SystemSnapshot(sampledAt: Date(), uptime: now,
            thermalState: thermalDescription(), cpu: cpu, memory: memory, disk: disk,
            network: network, battery: systemBatteryReading(), processes: systemProcesses(),
            unavailable: unavailable)
    }

    private func cpuTicks() -> [[UInt64]]? {
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &processorCount, &info, &count) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        guard count >= processorCount * 4 else { return nil }
        return (0..<Int(processorCount)).map { core in
            (0..<4).map { UInt64(UInt32(bitPattern: info[core * 4 + $0])) }
        }
    }

    private func memoryReading() -> SystemMemoryReading? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        let total = ProcessInfo.processInfo.physicalMemory
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        var pressure: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let pressureResult = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, nil, 0)
        let state: SystemMemoryPressure = pressureResult != 0 ? .unknown :
            pressure >= 4 ? .critical : pressure >= 2 ? .warning : .normal
        return SystemMemoryReading(used: min(total, pages * UInt64(pageSize)), total: total, pressure: state)
    }

    private func diskReading() -> SystemDiskReading? {
        var home = FileManager.default.homeDirectoryForCurrentUser
        home.removeAllCachedResourceValues()
        guard let values = try? home.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]), let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return SystemDiskReading(total: Int64(total), available: available)
    }

    private func thermalDescription() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "溫控正常"
        case .fair: "機身溫熱"
        case .serious: "溫度偏高"
        case .critical: "系統正在降溫"
        @unknown default: "無法取得溫控狀態"
        }
    }
}
