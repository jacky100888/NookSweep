import NookSweepCore
import SwiftUI

struct StatusSparkline: View {
    let values: [Double]
    var maximum: Double? = nil
    var color: Color = .teal

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard values.count > 1 else { return }
                let peak = max(maximum ?? values.max() ?? 1, 0.0001)
                for (index, value) in values.enumerated() {
                    let point = CGPoint(x: proxy.size.width * Double(index) / Double(values.count - 1),
                        y: proxy.size.height * (1 - min(1, max(0, value / peak))))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .frame(height: 30).accessibilityHidden(true)
    }
}

struct StatusMetric<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12, content: content)
                .frame(maxWidth: .infinity, alignment: .leading).padding(5)
        } label: { Label(title, systemImage: symbol).foregroundStyle(.secondary) }
    }
}

struct StatusCoreBars: View {
    let cores: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(cores.enumerated()), id: \.offset) { index, fraction in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fraction > 0.85 ? Color.orange : Color.teal)
                        .frame(height: max(2, 26 * fraction))
                }
                .frame(height: 26).frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 2))
                .help("核心 \(index + 1)：\(fraction.formatted(.percent.precision(.fractionLength(0))))")
            }
        }
        .accessibilityLabel("各核心使用率")
        .accessibilityValue(cores.enumerated().map {
            "核心 \($0.offset + 1) \($0.element.formatted(.percent.precision(.fractionLength(0))))"
        }.joined(separator: "，"))
    }
}

struct StatusProcessList: View {
    let processes: [SystemProcessReading]
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 9 : 13) {
            ForEach(processes.prefix(compact ? 4 : 6)) { process in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(process.name).lineLimit(1)
                        if !compact { Text("PID \(process.pid)").font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 8)
                    Text(statusBytes(process.residentBytes)).monospacedDigit()
                }
                .font(compact ? .caption : .subheadline)
            }
            if processes.isEmpty {
                Text("沒有可讀取的程序資訊").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
