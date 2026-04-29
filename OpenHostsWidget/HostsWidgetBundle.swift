import WidgetKit
import SwiftUI

struct HostsWidgetEntry: TimelineEntry {
    let date: Date
}

struct HostsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HostsWidgetEntry { HostsWidgetEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (HostsWidgetEntry) -> Void) {
        completion(HostsWidgetEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HostsWidgetEntry>) -> Void) {
        completion(Timeline(entries: [HostsWidgetEntry(date: .now)], policy: .never))
    }
}

struct HostsWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "network.badge.shield.half.filled")
                .symbolRenderingMode(.hierarchical)
                .font(.title2)
            Spacer()
            Text("OpenHosts").font(.caption.bold())
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct HostsWidget: Widget {
    let kind = "com.debuginn.OpenHosts.Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HostsWidgetProvider()) { _ in
            HostsWidgetView()
        }
        .configurationDisplayName("OpenHosts")
        .description("Quick access to OpenHosts.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct OpenHostsWidgetBundle: WidgetBundle {
    var body: some Widget { HostsWidget() }
}
