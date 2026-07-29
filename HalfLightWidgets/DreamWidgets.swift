//
//  DreamWidgets.swift
//  HalfLightWidgets
//
//  The home-screen and lock-screen widgets for HalfLight: a streak + journal CTA,
//  the latest dream, at-a-glance stats, and a nightly prompt. All read the shared
//  DreamSnapshot; the CTA surfaces tap straight into a blank entry via
//  JournalDreamIntent (foregrounds the app, no dictation).
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Shared helpers

/// Wrap content so tapping it launches the app onto a new, blank dream entry.
/// Works on system and accessoryCircular / accessoryRectangular families.
private struct JournalButton<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Button(intent: JournalDreamIntent()) { content }
            .buttonStyle(.plain)
    }
}

private extension WidgetFamily {
    var isSystem: Bool {
        switch self {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge: true
        default: false
        }
    }
}

/// The atmospheric backdrop for home-screen widgets: a soft vertical gradient lit
/// by a warm glow in the top-trailing corner, with a scatter of faint stars — a
/// still, lightweight echo of the app's night sky.
private struct DreamWidgetBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.dreamBase, Color.dreamBaseDeep],
                startPoint: .top,
                endPoint: .bottom
            )

            // The "light" — a soft halo bleeding in from the top-trailing corner.
            RadialGradient(
                colors: [Color.dreamPrimary.opacity(0.55), Color.dreamPrimary.opacity(0.0)],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 150
            )
            .blendMode(.plusLighter)

            // A cooler secondary glow low-left for a touch of depth.
            RadialGradient(
                colors: [Color.dreamAccent.opacity(0.30), Color.dreamAccent.opacity(0.0)],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 130
            )

            Stars()
        }
    }

    /// A handful of static, faint stars placed by fraction of the tile.
    private struct Stars: View {
        private let points: [(x: CGFloat, y: CGFloat, r: CGFloat, o: Double)] = [
            (0.18, 0.22, 1.4, 0.7), (0.62, 0.16, 1.0, 0.5), (0.82, 0.42, 1.6, 0.6),
            (0.30, 0.62, 1.1, 0.45), (0.50, 0.80, 1.3, 0.55), (0.88, 0.74, 1.0, 0.4),
            (0.10, 0.84, 1.2, 0.5)
        ]
        var body: some View {
            GeometryReader { geo in
                ForEach(points.indices, id: \.self) { i in
                    let p = points[i]
                    Circle()
                        .fill(Color.dreamText.opacity(p.o))
                        .frame(width: p.r * 2, height: p.r * 2)
                        .position(x: geo.size.width * p.x, y: geo.size.height * p.y)
                }
            }
        }
    }
}

private extension View {
    /// Standard container background: the atmospheric backdrop for home-screen
    /// widgets, transparent for the lock-screen accessory families.
    func dreamWidgetBackground(_ family: WidgetFamily) -> some View {
        containerBackground(for: .widget) {
            if family.isSystem { DreamWidgetBackdrop() } else { Color.clear }
        }
    }
}

private func daysLabel(_ count: Int) -> String { count == 1 ? "day" : "days" }

// MARK: - Streak + journal CTA

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HalfLightStreakWidget", provider: DreamProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak & Journal")
        .description("Your journaling streak — tap to journal a dream.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DreamEntry
    private var streak: Int { entry.snapshot.currentStreak }

    var body: some View {
        content.dreamWidgetBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Label("\(streak)-day streak", systemImage: "flame.fill")
        case .accessoryCircular:
            JournalButton { circular }
        case .accessoryRectangular:
            JournalButton { rectangular }
        case .systemMedium:
            JournalButton { medium }
        default:
            JournalButton { small }
        }
    }

    private var journalPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.and.pencil")
            Text("Journal")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.dreamOnPrimary)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color.dreamPrimary, in: .capsule)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text("Streak")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dreamSubtle)
            }
            Spacer()
            Text("\(streak)")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(Color.dreamText)
            Text(daysLabel(streak))
                .font(.system(size: 14))
                .foregroundStyle(Color.dreamSubtle)
            Spacer()
            journalPill
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                    Text("Streak")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.dreamSubtle)
                }
                Spacer()
                Text("\(streak)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.dreamText)
                Text("\(daysLabel(streak)) in a row")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dreamSubtle)
                Spacer()
            }
            VStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 26, weight: .semibold))
                Text("Journal a dream")
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.dreamOnPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dreamPrimary, in: .rect(cornerRadius: 18))
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill").font(.system(size: 13))
                Text("\(streak)").font(.system(size: 19, weight: .bold, design: .rounded))
                Text(daysLabel(streak)).font(.system(size: 8))
            }
        }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill").font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(streak)-day streak").font(.headline)
                Text("Tap to journal a dream").font(.caption2)
            }
            Spacer()
        }
    }
}

// MARK: - Latest dream

struct LastDreamWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HalfLightLastDreamWidget", provider: DreamProvider()) { entry in
            LastDreamWidgetView(entry: entry)
        }
        .configurationDisplayName("Latest Dream")
        .description("A glance at the last dream you recorded.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

struct LastDreamWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DreamEntry

    private var moodColor: Color {
        Color(hex: entry.snapshot.lastDreamMoodColor ?? 0xE8A95C)
    }

    var body: some View {
        content.dreamWidgetBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        if let title = entry.snapshot.lastDreamTitle {
            switch family {
            case .accessoryRectangular: rectangular(title: title)
            default: medium(title: title)
            }
        } else {
            empty
        }
    }

    private func medium(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LATEST DREAM")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Color.dreamSubtle)
            Text(title)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Color.dreamText)
                .lineLimit(2)
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                if let mood = entry.snapshot.lastDreamMood,
                   let symbol = entry.snapshot.lastDreamMoodSymbol {
                    HStack(spacing: 5) {
                        Image(systemName: symbol)
                        Text(mood)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(moodColor.opacity(0.20), in: .capsule)
                    .foregroundStyle(moodColor)
                }
                Spacer()
                if let date = entry.snapshot.lastDreamDate {
                    Text(date, format: .relative(presentation: .named))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dreamSubtle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rectangular(title: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Latest dream", systemImage: entry.snapshot.lastDreamMoodSymbol ?? "moon.stars.fill")
                .font(.caption2)
            Text(title).font(.headline).lineLimit(1)
            if let date = entry.snapshot.lastDreamDate {
                Text(date, format: .relative(presentation: .named))
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var empty: some View {
        JournalButton {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .font(.title)
                    .foregroundStyle(Color.dreamPrimary)
                Text("No dreams yet")
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Color.dreamText)
                Text("Tap to journal your first one.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dreamSubtle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Stats

struct StatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HalfLightStatsWidget", provider: DreamProvider()) { entry in
            StatsWidgetView(entry: entry)
        }
        .configurationDisplayName("Dream Stats")
        .description("Total dreams, lucid count, and this week at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StatsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DreamEntry
    private var snap: DreamSnapshot { entry.snapshot }

    var body: some View {
        content.dreamWidgetBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        if family == .systemMedium {
            HStack(spacing: 0) {
                stat("\(snap.totalDreams)", "Dreams", "book.fill")
                divider
                stat("\(snap.lucidCount)", "Lucid", "eye.fill")
                divider
                stat("\(snap.weekCount)", "This week", "calendar")
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("DREAM STATS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Color.dreamSubtle)
                compactStat("\(snap.totalDreams)", "dreams", "book.fill")
                compactStat("\(snap.lucidCount)", "lucid", "eye.fill")
                compactStat("\(snap.weekCount)", "this week", "calendar")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.dreamText.opacity(0.08)).frame(width: 1, height: 44)
    }

    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Color.dreamPrimary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.dreamText)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.dreamSubtle)
        }
        .frame(maxWidth: .infinity)
    }

    private func compactStat(_ value: String, _ label: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Color.dreamPrimary)
                .frame(width: 18)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.dreamText)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.dreamSubtle)
            Spacer()
        }
    }
}

// MARK: - Nightly prompt

struct PromptWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HalfLightPromptWidget", provider: DreamProvider()) { entry in
            PromptWidgetView(entry: entry)
        }
        .configurationDisplayName("Dream Prompt")
        .description("A nightly nudge to capture and reflect on your dreams.")
        .supportedFamilies([.systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct PromptWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DreamEntry

    var body: some View {
        content.dreamWidgetBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Label(entry.prompt, systemImage: "moon.stars.fill")
        case .accessoryRectangular:
            JournalButton {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Dream prompt", systemImage: "moon.stars.fill").font(.caption2)
                    Text(entry.prompt).font(.caption).lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            JournalButton { medium }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .font(.title2)
                .foregroundStyle(Color.dreamPrimary)
            Text(entry.prompt)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Color.dreamText)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            HStack(spacing: 5) {
                Image(systemName: "square.and.pencil")
                Text("Tap to journal")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.dreamPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Journal a dream (lock screen)

struct JournalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HalfLightRecordWidget", provider: DreamProvider()) { _ in
            JournalWidgetView()
        }
        .configurationDisplayName("Journal a Dream")
        .description("A one-tap shortcut to a blank dream entry.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct JournalWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.dreamWidgetBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            JournalButton {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil").font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Journal a dream").font(.headline)
                        Text("Capture it before it fades").font(.caption2)
                    }
                    Spacer()
                }
            }
        default:
            JournalButton {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Streak — small", as: .systemSmall) {
    StreakWidget()
} timeline: {
    DreamEntry(date: .now, snapshot: .sample, prompt: DreamPrompts.today())
}

#Preview("Latest — medium", as: .systemMedium) {
    LastDreamWidget()
} timeline: {
    DreamEntry(date: .now, snapshot: .sample, prompt: DreamPrompts.today())
}

#Preview("Stats — medium", as: .systemMedium) {
    StatsWidget()
} timeline: {
    DreamEntry(date: .now, snapshot: .sample, prompt: DreamPrompts.today())
}

#Preview("Prompt — rectangular", as: .accessoryRectangular) {
    PromptWidget()
} timeline: {
    DreamEntry(date: .now, snapshot: .sample, prompt: DreamPrompts.today())
}
