import SwiftUI

/// A render-safe replica of PortListView for ImageRenderer. It mirrors the real
/// layout using only pure SwiftUI primitives (no NSSegmentedControl / NSTextField
/// / NSPopUpButton / LazyVStack), which ImageRenderer cannot rasterize offscreen.
struct ShotView: View {
    let entries: [PortEntry]
    let selected: ScanMode

    var body: some View {
        VStack(spacing: 0) {
            segmented
            search
            Divider()
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    RowShot(entry: entry)
                    Divider()
                }
            }
            Divider()
            footer
        }
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(ScanMode.allCases) { mode in
                Text(mode.rawValue)
                    .font(.system(size: 12, weight: mode == selected ? .semibold : .regular))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        mode == selected
                            ? AnyView(RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5))
                            : AnyView(Color.clear)
                    )
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            Text("Filter by port or app").foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(entries.count) \(selected.rawValue.lowercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "arrow.clockwise").foregroundStyle(.primary)
            Image(systemName: "gearshape").foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct RowShot: View {
    let entry: PortEntry

    private var stopping: Bool { entry.detail == "stopping…" }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: ":\(entry.port)")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                    Text(entry.command)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    tag
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(verbatim: "PID \(entry.pid)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Kill")
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 6))
                .opacity(stopping ? 0.4 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(stopping ? 0.45 : 1)
    }

    private var subtitle: String {
        if let remote = entry.remote, !stopping {
            return "\(entry.label)  \u{2192}  \(remote)"
        }
        return entry.label
    }

    @ViewBuilder
    private var tag: some View {
        switch entry.exposure {
        case .local:   pill("local", .secondary)
        case .exposed: pill("exposed", .orange)
        }
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }
}
