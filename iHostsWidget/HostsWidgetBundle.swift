import WidgetKit
import SwiftUI

@main
struct iHostsWidgetBundle: WidgetBundle {
    var body: some Widget { EmptyWidget() }
}

struct EmptyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "placeholder", provider: PlaceholderProvider()) { _ in
            EmptyView()
        }
    }
}

struct PlaceholderProvider: TimelineProvider {
    struct Entry: TimelineEntry { let date = Date() }
    func placeholder(in context: Context) -> Entry { Entry() }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry()], policy: .never))
    }
}
