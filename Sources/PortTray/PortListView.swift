import SwiftUI
import AppKit

struct PortListView: View {
    @ObservedObject var store: PortStore
    @ObservedObject var loginItem: LoginItem

    @State private var mode: ScanMode
    @State private var query: String
    @State private var confirmID: String?
    /// Screenshot-only: shows this row in its hovered state.
    private let previewHoverID: String?
    @State private var spin = 0.0
    @FocusState private var searchFocused: Bool
    @Namespace private var tabPill

    private static let listHeight: CGFloat = 440

    init(store: PortStore, loginItem: LoginItem,
         mode: ScanMode = .listening, query: String = "",
         confirmID: String? = nil, previewHoverID: String? = nil) {
        self.store = store
        self.loginItem = loginItem
        _mode = State(initialValue: mode)
        _query = State(initialValue: query)
        _confirmID = State(initialValue: confirmID)
        self.previewHoverID = previewHoverID
    }

    // MARK: - Derived

    private var needle: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private var visibleGroups: [PortGroup] {
        let groups = store.snapshot.groups[mode] ?? []
        let q = needle
        guard !q.isEmpty else { return groups }
        return groups.compactMap { g in
            let groupHit = g.searchText.contains(q)
            var copy = g
            copy.rows = groupHit ? g.rows : g.rows.filter { $0.searchText.contains(q) }
            return copy.rows.isEmpty ? nil : copy
        }
    }

    // MARK: - Body

    var body: some View {
        let groups = visibleGroups
        VStack(spacing: 0) {
            header
            searchField
            hairline
            list(groups)
            hairline
            footer(groups)
        }
        .frame(width: 400)
        .background(PT.panel)
        .foregroundStyle(PT.text)
        .background(shortcuts)
        .onAppear { loginItem.refresh() }
        .onExitCommand {
            if confirmID != nil { withAnimation(PT.spring) { confirmID = nil } }
            else if !query.isEmpty { query = "" }
        }
    }

    private var hairline: some View {
        Rectangle().fill(PT.line).frame(height: 1)
    }

    /// ⌘F focuses the filter; ⌘R refreshes; ⌘1-3 switch tabs.
    private var shortcuts: some View {
        ZStack {
            Button("") { searchFocused = true }.keyboardShortcut("f")
            Button("") { refreshNow() }.keyboardShortcut("r")
            ForEach(Array(ScanMode.allCases.enumerated()), id: \.offset) { i, m in
                Button("") { pick(m) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(ScanMode.allCases) { tab($0) }
            }
            .padding(2)
            .background(PT.seg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            iconButton("arrow.clockwise", help: "Refresh now (⌘R)") { refreshNow() }
                .rotationEffect(.degrees(spin))

            Menu {
                Toggle("Open at Login", isOn: Binding(
                    get: { loginItem.enabled },
                    set: { loginItem.set($0) }
                ))
                Divider()
                Button("Quit PortTray") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 28, height: 28)
            .help("Settings")
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 8, trailing: 10))
    }

    private func tab(_ m: ScanMode) -> some View {
        let active = m == mode
        let count = store.snapshot.counts[m] ?? 0
        return Button { pick(m) } label: {
            HStack(spacing: 6) {
                Text(m.rawValue)
                Text(verbatim: "\(count)")
                    .font(.system(size: 11, weight: active ? .semibold : .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, active ? 5 : 0)
                    .background(active ? PT.chip : .clear,
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .foregroundStyle(PT.text2)
            }
            .font(.system(size: 12.5, weight: active ? .semibold : .medium))
            .foregroundStyle(active ? PT.text : PT.text2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(PT.segOn)
                        .shadow(color: PT.segShadow, radius: 1, y: 1)
                        .matchedGeometryEffect(id: "pill", in: tabPill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        HoverIcon(symbol: symbol, action: action).help(help)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PT.text2)
            TextField("", text: $query,
                      prompt: Text("Port, app or folder").foregroundColor(PT.ph))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            if query.isEmpty {
                Text("⌘F")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PT.text2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(PT.border, lineWidth: 1))
                    .transition(.opacity)
            } else {
                Button { query = "" } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PT.text2)
                        .padding(3)
                }
                .buttonStyle(PressStyle())
                .help("Clear filter")
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(PT.quick, value: query.isEmpty)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(PT.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(EdgeInsets(top: 0, leading: 12, bottom: 10, trailing: 12))
    }

    // MARK: - List

    private func list(_ groups: [PortGroup]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(groups) { g in
                    VStack(spacing: 0) {
                        groupHeader(g)
                        ForEach(g.rows) { r in
                            PortRowView(
                                row: r,
                                confirming: confirmID == r.id,
                                stopping: store.killing.contains(r.id),
                                forceHover: previewHoverID == r.id,
                                onAsk: { withAnimation(PT.spring) { confirmID = r.id } },
                                onCancel: { withAnimation(PT.spring) { confirmID = nil } },
                                onKill: {
                                    withAnimation(PT.spring) { confirmID = nil }
                                    store.kill(r, mode: mode)
                                })
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -6)),
                                removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .leading))))
                        }
                    }
                    .transition(.opacity)
                }
                if groups.isEmpty {
                    emptyState
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .padding(.bottom, 6)
            .animation(PT.spring, value: groups.map(\.id))
            .animation(PT.spring, value: groups.flatMap { $0.rows.map(\.id) })
        }
        .frame(height: Self.listHeight)
    }

    private func groupHeader(_ g: PortGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(g.title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.44)
            if !g.path.isEmpty {
                Text(g.path)
                    .font(.ptMono(11))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(verbatim: "\(g.rows.count) \(mode.unit(g.rows.count))")
                .font(.system(size: 11))
                .contentTransition(.numericText())
        }
        .foregroundStyle(PT.text2)
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 4, trailing: 14))
    }

    @ViewBuilder
    private var emptyState: some View {
        let q = needle
        if !store.loaded {
            ProgressView().controlSize(.small).padding(.top, 140)
        } else if !q.isEmpty, let port = Int(q), port > 0, port < 65536,
                  !store.snapshot.listeningPorts.contains(port) {
            FreePortView(port: port) {
                copy("localhost:\(port)")
                store.showToast("Copied localhost:\(port)")
            }
        } else if !q.isEmpty {
            Text("No matches for “\(query.trimmingCharacters(in: .whitespaces))”")
                .font(.system(size: 13))
                .foregroundStyle(PT.text2)
                .padding(.top, 110)
                .padding(.horizontal, 32)
        } else {
            Text("No \(mode.rawValue.lowercased()) \(mode.unit(0))")
                .font(.system(size: 13))
                .foregroundStyle(PT.text2)
                .padding(.top, 110)
        }
    }

    // MARK: - Footer

    private func footer(_ groups: [PortGroup]) -> some View {
        let total = groups.reduce(0) { $0 + $1.rows.count }
        let exposed = store.snapshot.exposedCount
        return HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if let toast = store.toast {
                    HStack(spacing: 6) {
                        Image(systemName: toast.isError ? "exclamationmark.circle" : "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text(toast.text).lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(toast.isError ? PT.red : PT.green)
                    .id(toast.id)
                    .transition(.asymmetric(
                        insertion: .offset(y: 10).combined(with: .opacity),
                        removal: .offset(y: -8).combined(with: .opacity)))
                } else if mode == .listening, exposed > 0, needle.isEmpty {
                    HStack(spacing: 6) {
                        Circle().fill(PT.orange).frame(width: 7, height: 7)
                        Text(verbatim: "\(exposed) reachable from your network")
                            .contentTransition(.numericText())
                    }
                    .transition(.opacity)
                } else {
                    Text(verbatim: "\(total) \(mode.unit(total))")
                        .contentTransition(.numericText())
                        .transition(.opacity)
                }
            }
            .foregroundStyle(PT.text2)
            Spacer(minLength: 8)
            Text("Live")
                .foregroundStyle(PT.text2)
                .help("Refreshes every few seconds while open")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .frame(height: 38)
        .clipped()
        .animation(PT.spring, value: store.toast)
    }

    // MARK: - Actions

    private func pick(_ m: ScanMode) {
        guard m != mode else { return }
        withAnimation(PT.spring) {
            mode = m
            confirmID = nil
        }
    }

    private func refreshNow() {
        withAnimation(.easeInOut(duration: 0.55)) { spin += 360 }
        store.refresh()
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

// MARK: - Row

struct PortRowView: View {
    let row: PortRow
    let confirming: Bool
    let stopping: Bool
    var forceHover = false
    let onAsk: () -> Void
    let onCancel: () -> Void
    let onKill: () -> Void

    @State private var hoverState = false
    private var hovering: Bool { hoverState || forceHover }

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: ":\(row.port)")
                .font(.ptMono(15, .semibold))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if row.exposed { NetworkBadge() }
                }
                Text(confirming
                     ? "Stop PID \(row.entry.pid)?"
                     : row.sub)
                    .font(.ptMono(11))
                    .foregroundStyle(confirming ? PT.red : PT.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .id(confirming)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(confirming ? PT.redBg : (hovering ? PT.hover : .clear))
        )
        .padding(.horizontal, 6)
        .opacity(stopping ? 0.45 : 1)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(PT.quick) { hoverState = h } }
        .help(confirming ? "Sends SIGTERM, then SIGKILL if it hangs" : row.entry.label)
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var trailing: some View {
        if confirming {
            HStack(spacing: 6) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(PT.panel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PT.border))
                }
                Button(action: onKill) {
                    Text("Kill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(PT.killRed, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(PressStyle())
            .transition(.asymmetric(
                insertion: .offset(x: 14).combined(with: .opacity),
                removal: .opacity))
        } else if stopping {
            ProgressView().controlSize(.small).frame(width: 56, height: 26, alignment: .trailing)
        } else {
            ZStack(alignment: .trailing) {
                Text(row.uptime)
                    .font(.system(size: 11.5))
                    .foregroundStyle(PT.text2)
                    .opacity(hovering ? 0 : 1)
                Button(action: onAsk) {
                    Text("Kill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PT.red)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(PT.redBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .opacity(hovering ? 1 : 0)
                .scaleEffect(hovering ? 1 : 0.92, anchor: .trailing)
                .allowsHitTesting(hovering)
                .accessibilityLabel("Kill \(row.name) on port \(row.port)")
            }
            .frame(width: 56, height: 26, alignment: .trailing)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Kill…", action: onAsk)
        if let url = row.entry.browserURL {
            Divider()
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
        }
        if let cwd = row.entry.cwd, cwd != "/" {
            Button("Reveal Folder in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
            }
        }
        Divider()
        Button("Copy Port") { copy("\(row.port)") }
        Button("Copy PID") { copy("\(row.entry.pid)") }
        Button("Copy Address") { copy(row.entry.address) }
        Button("Copy Command") { copy(row.entry.label) }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

// MARK: - Pieces

private struct NetworkBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "globe").font(.system(size: 9, weight: .semibold))
            Text("network")
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(PT.orange)
        .padding(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 6))
        .background(PT.orangeBg, in: Capsule())
        .fixedSize()
        .help("Reachable from your network")
    }
}

private struct HoverIcon: View {
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PT.text2)
                .frame(width: 28, height: 28)
                .background(hovering ? PT.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { h in withAnimation(PT.quick) { hovering = h } }
    }
}

private struct FreePortView: View {
    let port: Int
    let onCopy: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(PT.green)
                .frame(width: 44, height: 44)
                .background(PT.chip, in: Circle())
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)
            Text(verbatim: "Port \(port) is free")
                .font(.system(size: 15, weight: .semibold))
            Text(verbatim: "Nothing is listening on :\(port). Start your server, it will show up here within a few seconds.")
                .font(.system(size: 12.5))
                .foregroundStyle(PT.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onCopy) {
                Text(verbatim: "Copy localhost:\(port)")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(PT.panel, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(PT.border))
            }
            .buttonStyle(PressStyle())
            .padding(.top, 6)
        }
        .padding(EdgeInsets(top: 96, leading: 32, bottom: 0, trailing: 32))
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.05)) { appeared = true }
        }
    }
}
