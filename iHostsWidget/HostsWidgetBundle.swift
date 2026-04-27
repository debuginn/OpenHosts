import WidgetKit
import SwiftUI
import AppIntents
import SharedKit

// MARK: - Timeline Entry

struct HostsWidgetEntry: TimelineEntry {
    let date: Date
    let state: AppState
}

// MARK: - Provider

struct HostsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HostsWidgetEntry {
        HostsWidgetEntry(date: .now, state: .empty)
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (HostsWidgetEntry) -> Void) {
        completion(HostsWidgetEntry(date: .now, state: HostsStore().load()))
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<HostsWidgetEntry>) -> Void) {
        let entry = HostsWidgetEntry(date: .now, state: HostsStore().load())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Views

struct HostsWidgetView: View {
    let entry: HostsWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(state: entry.state)
        default:
            SmallWidgetView(state: entry.state)
        }
    }
}

struct SmallWidgetView: View {
    let state: AppState

    private var subtitle: String {
        if let id = state.activeProfileId,
           let profile = state.profiles.first(where: { $0.id == id }) {
            return profile.name
        }
        let count = state.modules.filter(\.isEnabled).count
        return "\(count) module\(count == 1 ? "" : "s") active"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "network.badge.shield.half.filled")
                .symbolRenderingMode(.hierarchical)
                .font(.title2)
            Spacer()
            Text("iHosts").font(.caption.bold())
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct MediumWidgetView: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("iHosts").font(.caption.bold())
            ForEach(state.modules.prefix(4)) { module in
                Button(intent: ToggleModuleIntent(moduleID: module.id.uuidString)) {
                    HStack {
                        Image(systemName: module.isEnabled
                              ? "checkmark.circle.fill" : "circle")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(module.isEnabled
                                             ? Color.accentColor : .secondary)
                        Text(module.name).font(.caption)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget + Bundle

struct HostsWidget: Widget {
    let kind = "com.debuginn.iHosts.Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HostsWidgetProvider()) { entry in
            HostsWidgetView(entry: entry)
        }
        .configurationDisplayName("iHosts")
        .description("Quickly toggle your hosts modules.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct iHostsWidgetBundle: WidgetBundle {
    var body: some Widget {
        HostsWidget()
    }
}
