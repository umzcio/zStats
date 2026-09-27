import SwiftUI
import StatsCore

struct ProjectsView: View {
    @EnvironmentObject var store: MonitorStore
    @State private var pending: [ProcessReading] = []
    @State private var confirm = false
    private var rows: [ProjectReading] { store.projects.filter { store.search.isEmpty || $0.name.localizedCaseInsensitiveContains(store.search) || $0.ports.contains { String($0).contains(store.search) } } }
    var body: some View {
        Panel(padding: 12) {
            VStack(spacing: 5) {
                HStack(spacing: 12) {
                    Image(systemName: "terminal").foregroundStyle(Metric.projects.color).frame(width: 30, height: 30).background(Metric.projects.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(store.projects.count) development servers are listening").font(.system(size: 12, weight: .semibold))
                        Text("\(Format.memory(store.projects.reduce(0) { $0 + $1.memory })) across \(Set(store.projects.flatMap(\.ports)).count) open ports.").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField("Find project or port", text: $store.search).textFieldStyle(.plain).font(.system(size: 11)).frame(width: 140)
                }.padding(12).background(Metric.projects.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                if rows.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "folder.badge.gearshape").font(.system(size: 36, weight: .light)).foregroundStyle(Metric.projects.color.opacity(0.7))
                        Text(store.search.isEmpty ? "No development servers found" : "No matching projects").font(.system(size: 16, weight: .medium))
                        Text("Listening development processes appear here with their working folder and ports.\nThe list refreshes every 20 seconds.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(rows) { project in
                                HStack(spacing: 12) {
                                    Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(Metric.projects.color).frame(width: 26, height: 26).background(Metric.projects.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(project.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                        Text(project.processes.first?.name ?? "Process").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }.frame(minWidth: 100, alignment: .leading)
                                    Spacer()
                                    ForEach(project.ports.prefix(4), id: \.self) { port in
                                        Text(String(port)).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Metric.projects.color).padding(.horizontal, 7).padding(.vertical, 4).background(Metric.projects.color.opacity(0.11), in: Capsule())
                                    }
                                    if project.cpu > 1 { Label("working", systemImage: "bolt.fill").font(.system(size: 9)).foregroundStyle(Metric.battery.color).padding(.horizontal, 7).padding(.vertical, 4).background(Metric.battery.color.opacity(0.1), in: Capsule()) }
                                    Text(Format.memory(project.memory)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().frame(width: 83, alignment: .trailing)
                                    Menu {
                                        if let path = project.directory { Button("Show in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }.disabled(store.referenceMode) }
                                        Button("Stop server…", role: .destructive) { pending = project.processes; confirm = true }.disabled(store.referenceMode)
                                    } label: { Image(systemName: "ellipsis").frame(width: 20) }.menuStyle(.borderlessButton).frame(width: 24)
                                }.padding(.horizontal, 12).padding(.vertical, 13).help(project.directory ?? "Working directory unavailable")
                            }
                        }
                    }
                }
            }
        }.alert("Stop this development server?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Stop Server", role: .destructive) { store.terminate(pending, force: false) }
        } message: { Text("\(pending.count) processes will receive a termination request. Unsaved work may be lost.") }
    }
}
