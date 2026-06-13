import SwiftUI
import AppKit

struct PortListView: View {
    @ObservedObject var store: PortStore
    @ObservedObject var loginItem: LoginItem
    @State private var query = ""
    @State private var confirmKill: PortEntry?

    private let refreshTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var filtered: [PortEntry] {
        guard !query.isEmpty else { return store.entries }
        let q = query.trimmingCharacters(in: .whitespaces)
        return store.entries.filter {
            "\($0.port)".contains(q) || $0.command.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            modePicker
            searchField
            Divider()
            content
            if let message = store.statusMessage {
                Divider()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            Divider()
            footer
        }
        .frame(width: 380)
        .onAppear {
            store.refresh()
            loginItem.refresh()
        }
        .onReceive(refreshTimer) { _ in store.refresh() }
        .confirmationDialog(
            confirmKill.map { "Kill \($0.command) on port \($0.port)?" } ?? "",
            isPresented: Binding(
                get: { confirmKill != nil },
                set: { if !$0 { confirmKill = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let entry = confirmKill {
                Button("Kill", role: .destructive) { store.kill(entry) }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if let entry = confirmKill {
                Text("PID \(entry.pid) · \(entry.user)\n\(entry.label)")
            }
        }
    }

    private var modePicker: some View {
        Picker("", selection: $store.mode) {
            ForEach(ScanMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter by port or app", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            Text(store.entries.isEmpty ? "No \(store.mode.rawValue.lowercased()) ports" : "No matches")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { entry in
                        PortRow(entry: entry, onKill: { confirmKill = entry })
                        Divider()
                    }
                }
            }
            .frame(height: min(CGFloat(filtered.count) * 52, 360))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(store.entries.count) \(store.mode.rawValue.lowercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh now")

            Menu {
                Toggle("Open at Login", isOn: Binding(
                    get: { loginItem.enabled },
                    set: { loginItem.set($0) }
                ))
                Divider()
                Button("Quit PortTray") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct PortRow: View {
    let entry: PortEntry
    let onKill: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(":\(entry.port)")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                    Text(entry.command)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    exposureTag
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text("PID \(entry.pid)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Button("Kill", action: onKill)
                .controlSize(.small)
                .tint(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(entry.label)
        .contextMenu {
            Button("Kill", action: onKill)
            if let url = entry.browserURL {
                Divider()
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Copy PID") { copy("\(entry.pid)") }
            Button("Copy Port") { copy("\(entry.port)") }
            Button("Copy Address") { copy(entry.address) }
            Button("Copy Command") { copy(entry.label) }
        }
    }

    private var subtitle: String {
        if let remote = entry.remote {
            return "\(entry.label)  \u{2192}  \(remote)"
        }
        return entry.label
    }

    @ViewBuilder
    private var exposureTag: some View {
        switch entry.exposure {
        case .local:
            tag("local", color: .secondary)
        case .exposed:
            tag("exposed", color: .orange)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
