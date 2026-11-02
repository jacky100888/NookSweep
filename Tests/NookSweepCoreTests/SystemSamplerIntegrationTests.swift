import Testing
import NookSweepCore

@Test func systemSamplerReadsKernelCountersOnTheCurrentArchitecture() async throws {
    let sampler = SystemSampler()
    _ = await sampler.sample()
    // CPU 計數器以系統 tick 更新，需跨過取樣間隔。
    try await Task.sleep(for: .milliseconds(100))
    let snapshot = await sampler.sample()
    let memory = try #require(snapshot.memory)
    #expect(memory.total > 0)
    #expect(memory.used <= memory.total)
    let cpu = try #require(snapshot.cpu)
    #expect(!cpu.cores.isEmpty)
    #expect(cpu.fraction.isFinite && (0...1).contains(cpu.fraction))
    #expect(cpu.cores.allSatisfy { $0.isFinite && (0...1).contains($0) })
    #expect(snapshot.uptime > 0)
}
