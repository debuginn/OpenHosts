import WidgetKit
import SwiftUI
import SharedKit

struct HostsWidgetEntry: TimelineEntry {
    let date: Date
    let items: [WidgetConfigItem]
}

struct HostsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HostsWidgetEntry {
        HostsWidgetEntry(date: .now, items: [
            WidgetConfigItem(id: UUID(), name: "Example", isEnabled: true, isGroup: false),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (HostsWidgetEntry) -> Void) {
        let items = WidgetState.read()?.items ?? []
        completion(HostsWidgetEntry(date: .now, items: items))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HostsWidgetEntry>) -> Void) {
        let items = WidgetState.read()?.items ?? []
        let entry = HostsWidgetEntry(date: .now, items: items)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Item Card

struct ItemCardView: View {
    let item: WidgetConfigItem
    let compact: Bool

    private var accentColor: Color {
        item.isGroup ? .orange : .blue
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: item.isGroup ? "folder.fill" : "doc.text.fill")
                .font(.caption2)
                .foregroundStyle(item.isEnabled ? accentColor : .gray)
                .frame(width: 14, alignment: .center)
            Text(item.name)
                .font(.caption2)
                .fontWeight(compact ? .regular : .medium)
                .lineLimit(1)
                .foregroundStyle(item.isEnabled ? .primary : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(item.isEnabled ? accentColor.opacity(0.12) : Color.gray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(item.isEnabled ? accentColor.opacity(0.25) : Color.clear, lineWidth: 0.5)
        )
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: HostsWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "apple.terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("OpenHosts")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            if entry.items.isEmpty {
                Spacer()
                Text("No items")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.items.prefix(4)) { item in
                    ItemCardView(item: item, compact: true)
                }
                if entry.items.count > 4 {
                    Text("+\(entry.items.count - 4) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: HostsWidgetEntry

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "apple.terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("OpenHosts")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                let enabled = entry.items.filter(\.isEnabled).count
                Text("\(enabled)/\(entry.items.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if entry.items.isEmpty {
                Spacer()
                Text("No items configured")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(entry.items.prefix(6)) { item in
                        Button(intent: ToggleConfigIntent(itemID: item.id)) {
                            ItemCardView(item: item, compact: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if entry.items.count > 6 {
                    Text("+\(entry.items.count - 6) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Entry View

struct HostsWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: HostsWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                MediumWidgetView(entry: entry)
            default:
                SmallWidgetView(entry: entry)
            }
        }
        .widgetURL(URL(string: "openhosts://open-editor"))
    }
}

// MARK: - Widget

struct HostsWidget: Widget {
    let kind = "com.debuginn.OpenHosts.Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HostsWidgetProvider()) { entry in
            HostsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("OpenHosts")
        .description("View and toggle your hosts configs.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct OpenHostsWidgetBundle: WidgetBundle {
    var body: some Widget { HostsWidget() }
}
