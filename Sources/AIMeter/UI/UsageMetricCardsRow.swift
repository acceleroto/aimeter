import SwiftUI

/// Lays out usage metric cards in one row with equal height matching the tallest card's content.
struct UsageMetricCardsRow: View {
    let metrics: [UsageMetric]
    let resetText: (UsageMetric) -> String?

    @State private var rowHeight: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(metrics, id: \.title) { metric in
                UsageMetricCard(
                    title: metric.title,
                    value: metric.value,
                    subtitle: resetText(metric)
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: UsageMetricCardHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                )
                .frame(height: rowHeight > 0 ? rowHeight : nil, alignment: .top)
            }
        }
        .onPreferenceChange(UsageMetricCardHeightPreferenceKey.self) { height in
            guard height > 0, abs(height - rowHeight) > 0.5 else {
                return
            }
            rowHeight = height
        }
    }
}

private struct UsageMetricCard: View {
    let title: String
    let value: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }
}

private enum UsageMetricCardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
