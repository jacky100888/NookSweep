import Foundation
import Testing
@testable import NookSweepCore

@Test func cpuUsageUsesIntervalsRatherThanLifetimeTotals() throws {
    let previous: [[UInt64]] = [[1000, 500, 5000, 0], [2000, 600, 5000, 0]]
    let current: [[UInt64]] = [[1020, 510, 5070, 0], [2040, 620, 5040, 0]]
    let result = try #require(SystemCPUReading.calculate(previous: previous, current: current))
    #expect(abs(result.fraction - 0.45) < 0.0001)
    #expect(result.cores == [0.3, 0.6])
}

@Test func cpuCounterResetsAndMissingCoresDoNotProduceInvalidLoad() {
    #expect(SystemCPUReading.calculate(previous: [[100, 100, 100, 0]], current: [[1, 1, 1, 0]]) == nil)
    #expect(SystemCPUReading.calculate(previous: [], current: [[1, 1, 1, 0]]) == nil)
    #expect(SystemCPUReading.calculate(previous: [[1, 1, 1, 0]], current: [[1, 1, 1, 0]]) == nil)
}

@Test func networkRatesUseElapsedTimeAndDiscardResetSamples() {
    #expect(SystemNetworkReading.rate(previous: 1024, current: 5120, elapsed: 2) == 2048)
    #expect(SystemNetworkReading.rate(previous: 5120, current: 10, elapsed: 2) == nil)
    #expect(SystemNetworkReading.rate(previous: 0, current: 10, elapsed: 0) == nil)
    #expect(SystemNetworkReading.rate(previous: 0, current: 10, elapsed: .infinity) == nil)
}
