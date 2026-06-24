import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum DashboardLayout {
    static let width: CGFloat = 326
    static let minHeight: CGFloat = 278
    static let maxHeight: CGFloat = 438
    static let cornerRadius: CGFloat = 18

    static func size(visibleCount: Int, showsError: Bool) -> NSSize {
        NSSize(width: width, height: height(visibleCount: visibleCount, showsError: showsError))
    }

    static func height(visibleCount: Int, showsError: Bool) -> CGFloat {
        let clampedVisibleCount = max(visibleCount, 1)
        let headerHeight: CGFloat = 48
        let footerHeight: CGFloat = 44
        let rowHeight: CGFloat = 49
        let errorHeight: CGFloat = showsError ? 50 : 0
        let contentHeight = headerHeight + footerHeight + CGFloat(clampedVisibleCount) * rowHeight + errorHeight + 12
        return min(maxHeight, max(minHeight, ceil(contentHeight)))
    }
}

struct DashboardView: View {
    @ObservedObject var store: SwitchStore
    @State private var dashboardDragging: SwitchKind?
    @State private var dashboardDropPlacement: DashboardDropPlacement?

    private var panelSize: NSSize {
        DashboardLayout.size(visibleCount: store.visibleKinds.count, showsError: store.lastError != nil)
    }

    private var activeCount: Int {
        store.visibleKinds.filter { store.snapshots[$0]?.isOn == true }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            DashboardHeader(store: store, activeCount: activeCount)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(DashboardBandBackground(placement: .header))

            Rectangle()
                .fill(DashboardColors.separator)
                .frame(height: 1)

            Group {
                if store.visibleKinds.isEmpty {
                    EmptyDashboardView(store: store)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.visibleKinds.enumerated()), id: \.element.id) { index, kind in
                                DashboardReorderRow(
                                    kind: kind,
                                    store: store,
                                    showsSeparator: index < store.visibleKinds.count - 1,
                                    dragging: $dashboardDragging,
                                    dropPlacement: $dashboardDropPlacement
                                )
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 7)
                        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: dashboardDropPlacement)
                        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: store.visibleKinds)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if let error = store.lastError {
                DashboardErrorBanner(message: error, store: store)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 7)
            }

            FooterBar(store: store)
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .background {
            DashboardBackdrop()
        }
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DashboardLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardLayout.cornerRadius, style: .continuous)
                .stroke(DashboardColors.border, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: DashboardLayout.cornerRadius, style: .continuous)
                .stroke(DashboardColors.highlight, lineWidth: 1)
                .blendMode(.screen)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
        .environment(\.locale, Locale(identifier: store.effectiveLanguage.localeIdentifier))
    }
}

private struct DashboardReorderRow: View {
    let kind: SwitchKind
    @ObservedObject var store: SwitchStore
    let showsSeparator: Bool
    @Binding var dragging: SwitchKind?
    @Binding var dropPlacement: DashboardDropPlacement?

    private var snapshot: SwitchSnapshot {
        store.snapshots[kind] ?? .off
    }

    private var showsDropBefore: Bool {
        dropPlacement == DashboardDropPlacement(item: kind, position: .before)
    }

    private var showsDropAfter: Bool {
        dropPlacement == DashboardDropPlacement(item: kind, position: .after)
    }

    var body: some View {
        VStack(spacing: 0) {
            DashboardDropSlot(isVisible: showsDropBefore)
            ControlRow(
                kind: kind,
                store: store,
                showsSeparator: showsSeparator,
                isDragging: dragging == kind,
                dragProvider: {
                    withAnimation(.easeOut(duration: 0.12)) {
                        dragging = kind
                        dropPlacement = nil
                    }
                    return NSItemProvider(object: kind.rawValue as NSString)
                }
            )
            DashboardDropSlot(isVisible: showsDropAfter)
        }
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.text],
            delegate: DashboardDropDelegate(
                item: kind,
                store: store,
                rowHeight: ControlRow.rowHeight(for: snapshot),
                topInset: showsDropBefore ? DashboardDropSlot.height : 0,
                dragging: $dragging,
                placement: $dropPlacement
            )
        )
    }
}

private struct DashboardDropPlacement: Equatable {
    enum Position: Equatable {
        case before
        case after
    }

    let item: SwitchKind
    let position: Position
}

private struct DashboardDropSlot: View {
    static let height: CGFloat = 18
    let isVisible: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
            Capsule()
                .fill(Color.accentColor.opacity(0.60))
                .frame(width: 48, height: 2)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(height: isVisible ? Self.height : 0)
        .opacity(isVisible ? 1 : 0)
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct EmptyDashboardView: View {
    let store: SwitchStore

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: "switch.2")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 58, height: 58)
                .background(DashboardColors.controlFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(store.text(.noSwitchAdded))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)

            Text(store.text(.selectSwitchPrompt))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DashboardColors.subtleText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 210)

            Button {
                store.preferredPreferencesTab = "customize"
                NotificationCenter.default.post(name: .openMacSwitchPreferences, object: nil)
            } label: {
                Text(store.text(.customize))
                    .font(.system(size: 12.5, weight: .bold))
                    .frame(width: 112, height: 30)
                    .background(DashboardColors.controlFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private enum DashboardColors {
    static let border = Color.primary.opacity(0.095)
    static let highlight = Color.white.opacity(0.26)
    static let separator = Color.primary.opacity(0.055)
    static let headerFill = Color.white.opacity(0.10)
    static let footerFill = Color.white.opacity(0.08)
    static let rowFill = Color.clear
    static let rowHoverFill = Color.white.opacity(0.15)
    static let rowOnFill = Color.accentColor.opacity(0.12)
    static let rowDragFill = Color.accentColor.opacity(0.16)
    static let controlFill = Color.white.opacity(0.20)
    static let controlHoverFill = Color.white.opacity(0.30)
    static let subtleText = Color.secondary.opacity(0.88)
    static let windowVeil = Color(nsColor: .windowBackgroundColor).opacity(0.08)
    static let glassGlow = Color.white.opacity(0.14)
    static let bottomShade = Color.black.opacity(0.035)
}

private struct DashboardBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: DashboardLayout.cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: DashboardLayout.cornerRadius, style: .continuous)
                    .fill(DashboardColors.windowVeil)
            }
            .overlay {
                LinearGradient(
                    colors: [
                        DashboardColors.glassGlow.opacity(colorScheme == .dark ? 0.10 : 1),
                        Color.clear,
                        DashboardColors.bottomShade.opacity(colorScheme == .dark ? 0.25 : 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.cornerRadius, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.cornerRadius, style: .continuous))
    }
}

private struct DashboardBandBackground: View {
    let placement: Placement

    enum Placement {
        case header
        case footer
    }

    var body: some View {
        ZStack {
            Color.clear
            LinearGradient(
                colors: colors,
                startPoint: placement == .header ? .top : .bottom,
                endPoint: placement == .header ? .bottom : .top
            )
        }
    }

    private var colors: [Color] {
        switch placement {
        case .header:
            return [
                DashboardColors.headerFill.opacity(1),
                DashboardColors.headerFill.opacity(0.40),
                Color.clear
            ]
        case .footer:
            return [
                DashboardColors.footerFill.opacity(0.95),
                DashboardColors.footerFill.opacity(0.46),
                Color.clear
            ]
        }
    }
}

private struct DashboardHeader: View {
    let store: SwitchStore
    let activeCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "switch.2")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mac Switch")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(activeCount == 0
                     ? L10n.controlsReady(store.visibleKinds.count, language: store.effectiveLanguage)
                     : L10n.activeOf(activeCount, total: store.visibleKinds.count, language: store.effectiveLanguage))
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(DashboardColors.subtleText)
            }

            Spacer()

            if activeCount > 0 {
                Text(L10n.onBadge(activeCount, language: store.effectiveLanguage))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(Color.accentColor.opacity(0.13), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            }

            CompactIconButton(symbol: "gearshape") {
                store.preferredPreferencesTab = "general"
                NotificationCenter.default.post(name: .openMacSwitchPreferences, object: nil)
            }
        }
        .frame(height: 30)
    }
}

private struct ControlRow: View {
    let kind: SwitchKind
    @ObservedObject var store: SwitchStore
    let showsSeparator: Bool
    let isDragging: Bool
    let dragProvider: (() -> NSItemProvider)?
    @State private var isHovering = false

    private var snapshot: SwitchSnapshot {
        store.snapshots[kind] ?? .off
    }

    private var hasDetailText: Bool {
        snapshot.warning != nil || snapshot.subtitle != nil
    }

    private var isRunning: Bool {
        store.isActionBusy(kind)
    }

    private var rowFixMessage: String? {
        let accessibilityPrompt = snapshot.warning == "Open System Settings"
            && (kind == .screenClean || kind == .lockKeyboard)
        guard snapshot.isAvailable == false || accessibilityPrompt else { return nil }
        let message = [kind.title, snapshot.warning, snapshot.subtitle]
            .compactMap { $0 }
            .joined(separator: " ")
        let lowercased = message.lowercased()
        guard !lowercased.contains("not supported"),
              !lowercased.contains("does not work on your current system"),
              !lowercased.contains("does not expose"),
              !lowercased.contains("does not allow"),
              !lowercased.contains("trash empty"),
              !lowercased.contains("pasteboard empty"),
              !lowercased.contains("no ejectable disks"),
              !lowercased.contains("no apps to hide"),
              !lowercased.contains("deriveddata: zero")
        else { return nil }
        return message
    }

    var body: some View {
        HStack(spacing: 9) {
            RowIdentityContent(
                kind: kind,
                title: store.switchTitle(kind),
                snapshot: snapshot,
                dragProvider: dragProvider
            )
                .layoutPriority(1)

            Spacer(minLength: 6)

            if kind == .keepAwake {
                KeepAwakeDurationMenu(store: store)
            } else if kind == .doNotDisturb {
                DoNotDisturbDurationMenu(store: store)
            }

            if let rowFixMessage {
                RowFixButton(remediation: ErrorFixRouter.remediation(for: rowFixMessage)) {
                    ErrorFixRouter.route(message: rowFixMessage, store: store)
                }
            } else if kind.isMomentaryAction {
                RowActionButton(kind: kind, isEnabled: snapshot.isAvailable, isRunning: isRunning) {
                    store.trigger(kind)
                }
            } else {
                Toggle("", isOn: Binding(
                    get: { snapshot.isOn },
                    set: { _ in store.toggle(kind) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(!snapshot.isAvailable || isRunning)
                .opacity(snapshot.isAvailable && !isRunning ? 1 : 0.52)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: Self.rowHeight(for: snapshot))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFill)
        )
        .overlay {
            if isHovering || snapshot.isOn || isDragging {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
        }
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(DashboardColors.separator)
                    .frame(height: 1)
                    .padding(.leading, 35)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu {
            Button {
                openSettingsDetail()
            } label: {
                Label("Settings...", systemImage: "slider.horizontal.3")
            }

            Button(role: .destructive) {
                store.setEnabled(kind, false)
            } label: {
                Label("Remove from Menu", systemImage: "eye.slash")
            }
            .disabled(store.isCustomizationBusy(kind) || store.visibleKinds.count <= 1)
        }
        .onHover { isHovering = $0 }
        .opacity(rowOpacity)
        .animation(.easeOut(duration: 0.12), value: isDragging)
    }

    private func openSettingsDetail() {
        store.preferredCustomizeKind = kind
        store.preferredPreferencesTab = "customize"
        NotificationCenter.default.post(name: .openMacSwitchPreferences, object: nil)
        store.clearLastError()
    }

    private var rowFill: Color {
        if isDragging {
            return DashboardColors.rowDragFill
        }
        if isHovering {
            return DashboardColors.rowHoverFill
        }
        if snapshot.isOn {
            return DashboardColors.rowOnFill
        }
        return DashboardColors.rowFill
    }

    private var rowOpacity: Double {
        if isDragging {
            return 0.58
        }
        if !snapshot.isAvailable {
            return 0.70
        }
        return isRunning ? 0.78 : 1
    }

    fileprivate static func rowHeight(for snapshot: SwitchSnapshot) -> CGFloat {
        snapshot.warning != nil || snapshot.subtitle != nil ? 49 : 43
    }
}

private struct RowIdentityContent: View {
    let kind: SwitchKind
    let title: String
    let snapshot: SwitchSnapshot
    let dragProvider: (() -> NSItemProvider)?

    var body: some View {
        HStack(spacing: 9) {
            SwitchGlyph(kind: kind, snapshot: snapshot)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let warning = snapshot.warning {
                    Text(warning)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.94, green: 0.04, blue: 0.16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else if let subtitle = snapshot.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DashboardColors.subtleText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .contentShape(Rectangle())
        .modifier(ConditionalDragModifier(dragProvider: dragProvider))
    }
}

private struct ConditionalDragModifier: ViewModifier {
    let dragProvider: (() -> NSItemProvider)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let dragProvider {
            content.onDrag(dragProvider)
        } else {
            content
        }
    }
}

private struct SwitchGlyph: View {
    let kind: SwitchKind
    let snapshot: SwitchSnapshot

    var body: some View {
        Image(systemName: kind.modernSymbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(iconColor)
            .frame(width: 24, height: 24)
    }

    private var iconColor: Color {
        if !snapshot.isAvailable {
            return Color.secondary.opacity(0.52)
        }
        if snapshot.isOn {
            return kind.accentColor
        }
        return Color.secondary
    }
}

private struct KeepAwakeDurationMenu: View {
    @ObservedObject var store: SwitchStore
    @State private var keepAwakeWhenLidClosed = KeepAwakePreferences.keepAwakeWhenLidClosed

    var body: some View {
        Menu {
            Button(KeepAwakeDuration.indefinitely.menuTitle) {
                store.keepAwakeDuration = .indefinitely
            }

            Divider()

            Toggle("Keep awake when the lid is closed", isOn: Binding(
                get: { keepAwakeWhenLidClosed },
                set: { value in
                    keepAwakeWhenLidClosed = value
                    KeepAwakePreferences.keepAwakeWhenLidClosed = value
                    if store.snapshots[.keepAwake]?.isOn == true {
                        store.set(.keepAwake, enabled: true)
                    } else {
                        store.refreshAsync(.keepAwake)
                    }
                }
            ))

            Divider()

            ForEach(KeepAwakeDuration.allCases.filter { $0 != .indefinitely }) { duration in
                Button(duration.menuTitle) {
                    store.keepAwakeDuration = duration
                }
            }
        } label: {
            DurationMenuLabel(title: store.keepAwakeDuration.compactDashboardTitle)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(store.isActionBusy(.keepAwake))
        .opacity(store.isActionBusy(.keepAwake) ? 0.55 : 1)
        .onAppear {
            keepAwakeWhenLidClosed = KeepAwakePreferences.keepAwakeWhenLidClosed
        }
    }
}

private struct DoNotDisturbDurationMenu: View {
    @ObservedObject var store: SwitchStore

    var body: some View {
        Menu {
            ForEach(DoNotDisturbDuration.allCases) { duration in
                Button(duration.menuTitle) {
                    store.doNotDisturbDuration = duration
                }
            }
        } label: {
            DurationMenuLabel(title: store.doNotDisturbDuration.compactDashboardTitle)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(store.isActionBusy(.doNotDisturb))
        .opacity(store.isActionBusy(.doNotDisturb) ? 0.55 : 1)
    }
}

private struct DurationMenuLabel: View {
    let title: String
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8.5, weight: .bold))
        }
        .foregroundStyle(.secondary)
        .frame(width: 50, height: 23)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
        .background(isHovering ? DashboardColors.controlHoverFill : DashboardColors.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.055), lineWidth: 1))
        .onHover { isHovering = $0 }
    }
}

private struct RowActionButton: View {
    let kind: SwitchKind
    let isEnabled: Bool
    let isRunning: Bool
    let action: () -> Void
    @State private var isHovering = false

    private var accent: Color { kind.accentColor }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRunning {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.64)
                } else {
                    Image(systemName: kind.actionSymbol)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(isEnabled ? accent : Color.secondary)
                }
            }
            .frame(width: 34, height: 23)
            .background(isHovering ? DashboardColors.controlHoverFill : DashboardColors.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.055), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isRunning)
        .opacity(isEnabled ? 1 : 0.52)
        .onHover { isHovering = $0 }
    }
}

private struct RowFixButton: View {
    let remediation: ErrorRemediation?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: remediation?.symbol ?? "wrench.and.screwdriver")
                    .font(.system(size: 10, weight: .bold))
                Text("Fix")
                    .font(.system(size: 10.5, weight: .bold))
            }
            .foregroundStyle(Color.accentColor)
            .frame(width: 42, height: 23)
            .background(isHovering ? DashboardColors.controlHoverFill : DashboardColors.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.055), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(remediation?.title ?? "Open Settings")
        .onHover { isHovering = $0 }
    }
}

private struct DashboardErrorBanner: View {
    let message: String
    @ObservedObject var store: SwitchStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color(red: 0.92, green: 0.16, blue: 0.20))

            Text(message)
                .font(.system(size: 11.2, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.84)

            Spacer(minLength: 4)

            Button {
                routeFix()
            } label: {
                Label("Fix", systemImage: "wrench.and.screwdriver")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                store.clearLastError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DashboardColors.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.red.opacity(0.16), lineWidth: 1)
        )
        .help(message)
    }

    private func routeFix() {
        ErrorFixRouter.route(message: message, store: store)
    }
}

private struct ErrorRemediation {
    let title: String
    let symbol: String
}

private enum ErrorFixRouter {
    static func remediation(for message: String) -> ErrorRemediation? {
        let lowercased = message.lowercased()
        if lowercased.contains("automation") || lowercased.contains("apple events") {
            return ErrorRemediation(title: "Open Automation", symbol: "gearshape")
        }
        if lowercased.contains("accessibility") || lowercased.contains("input event tap")
            || lowercased.contains("screen clean") || lowercased.contains("lock keyboard") {
            return ErrorRemediation(title: "Open Accessibility", symbol: "gearshape")
        }
        if lowercased.contains("do not disturb") || lowercased.contains("shortcut") || lowercased.contains("focus") {
            return ErrorRemediation(title: "Open DND Setup", symbol: "moon")
        }
        if lowercased.contains("play music") || lowercased.contains("spotify") || lowercased.contains("itunes")
            || lowercased.contains("music is not installed") || lowercased.contains("open music") {
            return ErrorRemediation(title: "Open Music Setup", symbol: "music.note")
        }
        if lowercased.contains("headphones") || lowercased.contains("audio device") || lowercased.contains("device not found") {
            return ErrorRemediation(title: "Open Bluetooth Audio", symbol: "headphones")
        }
        if lowercased.contains("bluetooth") {
            return ErrorRemediation(title: "Open Bluetooth", symbol: "antenna.radiowaves.left.and.right")
        }
        if lowercased.contains("display") || lowercased.contains("resolution") || lowercased.contains("true tone") {
            return ErrorRemediation(title: "Open Displays", symbol: "display")
        }
        if lowercased.contains("microphone") || lowercased.contains("input device") || lowercased.contains("sound") {
            return ErrorRemediation(title: "Open Sound", symbol: "speaker.wave.2")
        }
        if lowercased.contains("power") || lowercased.contains("energy") || lowercased.contains("battery")
            || lowercased.contains("disable sleep") || lowercased.contains("lid-closed sleep")
            || lowercased.contains("pmset") {
            return ErrorRemediation(title: "Open Battery", symbol: "battery.50percent")
        }
        if lowercased.contains("deriveddata") || lowercased.contains("xcode") {
            return ErrorRemediation(title: "Reveal DerivedData", symbol: "folder")
        }
        if lowercased.contains("trash") {
            return ErrorRemediation(title: "Open Trash", symbol: "trash")
        }
        if lowercased.contains("eject") || lowercased.contains("disk") {
            return ErrorRemediation(title: "Open Disk Utility", symbol: "internaldrive")
        }
        if lowercased.contains("stage manager") || lowercased.contains("widget") || lowercased.contains("dock")
            || lowercased.contains("desktop") || lowercased.contains("finder")
            || lowercased.contains("appleshowallfiles") || lowercased.contains("createdesktop")
            || lowercased.contains("autohide") || lowercased.contains("globallyenabled") {
            return ErrorRemediation(title: "Open Desktop & Dock", symbol: "dock.rectangle")
        }
        if lowercased.contains("lock screen") || lowercased.contains("screen saver") {
            return ErrorRemediation(title: "Open Lock Screen", symbol: "lock.display")
        }
        if lowercased.contains("location") {
            return ErrorRemediation(title: "Open Location", symbol: "location")
        }
        if lowercased.contains("start at login") || lowercased.contains("launch agent") || lowercased.contains("login item") {
            return ErrorRemediation(title: "Open Login Items", symbol: "person.crop.circle.badge.checkmark")
        }
        return ErrorRemediation(title: "Open Settings", symbol: "switch.2")
    }

    static func route(message: String, store: SwitchStore) {
        let lowercased = message.lowercased()
        if lowercased.contains("start at login") || lowercased.contains("launch agent") || lowercased.contains("login item") {
            clearLastErrorIfOpened(SystemSettingsLinks.openLoginItems(), store: store)
            store.refreshStartAtLoginStatusAsync()
            return
        }
        if lowercased.contains("automation") || lowercased.contains("apple events") {
            clearLastErrorIfOpened(AutomationPermission.openSettings(), store: store)
            return
        }
        if lowercased.contains("accessibility") || lowercased.contains("input event tap")
            || lowercased.contains("screen clean") || lowercased.contains("lock keyboard") {
            clearLastErrorIfOpened(AccessibilityPermission.requestAndOpenSettings(), store: store)
            return
        }
        if lowercased.contains("do not disturb") || lowercased.contains("shortcut") || lowercased.contains("focus") {
            openCustomize(.doNotDisturb, store: store)
            return
        }
        if lowercased.contains("play music") || lowercased.contains("spotify") || lowercased.contains("itunes")
            || lowercased.contains("music is not installed") || lowercased.contains("open music") {
            openCustomize(.playMusic, store: store)
            return
        }
        if lowercased.contains("headphones") || lowercased.contains("audio device") || lowercased.contains("device not found") {
            openCustomize(.bluetoothAudio, store: store)
            return
        }
        if lowercased.contains("bluetooth") {
            clearLastErrorIfOpened(SystemSettingsLinks.openBluetooth(), store: store)
            return
        }
        if lowercased.contains("display") || lowercased.contains("resolution") || lowercased.contains("true tone") {
            clearLastErrorIfOpened(SystemSettingsLinks.openDisplays(), store: store)
            return
        }
        if lowercased.contains("microphone") || lowercased.contains("input device") || lowercased.contains("sound") {
            clearLastErrorIfOpened(SystemSettingsLinks.openSound(), store: store)
            return
        }
        if lowercased.contains("power") || lowercased.contains("energy") || lowercased.contains("battery")
            || lowercased.contains("disable sleep") || lowercased.contains("lid-closed sleep")
            || lowercased.contains("pmset") {
            clearLastErrorIfOpened(SystemSettingsLinks.openBattery(), store: store)
            return
        }
        if lowercased.contains("deriveddata") || lowercased.contains("xcode") {
            clearLastErrorIfOpened(XcodeCleanPreferences.revealDerivedData(), store: store)
            return
        }
        if lowercased.contains("trash") {
            clearLastErrorIfOpened(TrashPreferences.openTrash(), store: store)
            return
        }
        if lowercased.contains("eject") || lowercased.contains("disk") {
            clearLastErrorIfOpened(openWorkspaceURL(AppLinks.diskUtility), store: store)
            return
        }
        if lowercased.contains("stage manager") || lowercased.contains("widget") || lowercased.contains("dock")
            || lowercased.contains("desktop") || lowercased.contains("finder")
            || lowercased.contains("appleshowallfiles") || lowercased.contains("createdesktop")
            || lowercased.contains("autohide") || lowercased.contains("globallyenabled") {
            clearLastErrorIfOpened(SystemSettingsLinks.openDesktopDock(), store: store)
            return
        }
        if lowercased.contains("lock screen") || lowercased.contains("screen saver") {
            clearLastErrorIfOpened(SystemSettingsLinks.openLockScreen(), store: store)
            return
        }
        if lowercased.contains("location") {
            clearLastErrorIfOpened(SystemSettingsLinks.openLocationServices(), store: store)
            return
        }

        store.preferredPreferencesTab = "general"
        NotificationCenter.default.post(name: .openMacSwitchPreferences, object: nil)
        store.clearLastError()
    }

    private static func clearLastErrorIfOpened(_ opened: Bool, store: SwitchStore) {
        if opened {
            store.clearLastError()
        }
    }

    private static func openCustomize(_ kind: SwitchKind, store: SwitchStore) {
        store.preferredCustomizeKind = kind
        store.preferredPreferencesTab = "customize"
        NotificationCenter.default.post(name: .openMacSwitchPreferences, object: nil)
        store.clearLastError()
    }
}

@discardableResult
private func reportOpenResult(_ opened: Bool, store: SwitchStore, failureMessage: String) -> Bool {
    if !opened {
        store.lastError = failureMessage
    } else if store.lastError == failureMessage {
        store.clearLastError()
    }
    return opened
}

@discardableResult
private func openWorkspaceURLOrReport(_ url: URL, store: SwitchStore, failureMessage: String) -> Bool {
    reportOpenResult(openWorkspaceURL(url), store: store, failureMessage: failureMessage)
}

private func scheduleAfterSwitchActionSettles(
    store: SwitchStore,
    kind: SwitchKind,
    delay: TimeInterval = 0.25,
    remainingAttempts: Int = 300,
    action: @escaping () -> Void
) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        if store.isActionBusy(kind), remainingAttempts > 0 {
            scheduleAfterSwitchActionSettles(
                store: store,
                kind: kind,
                delay: delay,
                remainingAttempts: remainingAttempts - 1,
                action: action
            )
            return
        }
        action()
    }
}

private extension SwitchKind {
    var actionSymbol: String {
        switch self {
        case .screenSaver: return "display"
        case .displaySleep: return "moon.zzz.fill"
        case .lockScreen: return "lock.fill"
        case .xcodeClean: return "hammer.fill"
        case .emptyTrash: return "trash.fill"
        case .ejectDisk: return "eject.fill"
        case .emptyPasteboard: return "doc.on.clipboard.fill"
        case .hideWindows: return "macwindow.on.rectangle"
        default: return "play.fill"
        }
    }
}

private struct FooterBar: View {
    let store: SwitchStore

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DashboardColors.separator)
                .frame(height: 1)

            ZStack {
                DashboardFooterButton(title: store.text(.customize)) {
                    store.preferredPreferencesTab = "customize"
                    NotificationCenter.default.post(name: .openMacSwitchPreferences, object: nil)
                }

                HStack {
                    Spacer()
                    CompactIconButton(symbol: "power") {
                        store.quit()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(DashboardBandBackground(placement: .footer))
    }
}

private struct DashboardFooterButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "square.grid.2x2")
                .font(.system(size: 12, weight: .medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary.opacity(0.78))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    isHovering ? DashboardColors.controlHoverFill : DashboardColors.controlFill.opacity(0.54),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.035), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct CompactIconButton: View {
    let symbol: String
    var isBusy = false
    var isDisabled = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.72)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(width: 28, height: 28)
            .background(
                isHovering ? DashboardColors.controlHoverFill : DashboardColors.controlFill.opacity(0.48),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(0.74))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.70 : 1)
        .onHover { isHovering = $0 }
    }
}

private extension KeepAwakeDuration {
    var compactDashboardTitle: String {
        switch self {
        case .indefinitely: return "All"
        case .fiveMinutes: return "5m"
        case .fifteenMinutes: return "15m"
        case .twentyFiveMinutes: return "25m"
        case .thirtyMinutes: return "30m"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        case .fiveHours: return "5h"
        case .eightHours: return "8h"
        }
    }
}

private extension DoNotDisturbDuration {
    var compactDashboardTitle: String {
        switch self {
        case .indefinitely: return "All"
        case .fiveMinutes: return "5m"
        case .fifteenMinutes: return "15m"
        case .twentyFiveMinutes: return "25m"
        case .thirtyMinutes: return "30m"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        case .fiveHours: return "5h"
        case .eightHours: return "8h"
        case .tomorrow: return "Tmr"
        }
    }
}

private extension SwitchKind {
    var modernSymbol: String {
        switch self {
        case .stageManager: return "rectangle.3.group.fill"
        case .hideWidgets: return "rectangle.grid.2x2"
        case .muteMicrophone: return "mic.slash.fill"
        case .hideDesktopIcons: return "square.grid.3x3.square"
        case .darkMode: return "moon.stars.fill"
        case .keepAwake: return "cup.and.saucer.fill"
        case .screenSaver: return "display"
        case .bluetoothAudio: return "headphones"
        case .doNotDisturb: return "moon.fill"
        case .nightShift: return "lightbulb.fill"
        case .trueTone: return "sun.max.fill"
        case .playMusic: return "music.note"
        case .showHiddenFiles: return "eye.fill"
        case .displaySleep: return "display.trianglebadge.exclamationmark"
        case .screenResolution: return "rectangle.inset.filled"
        case .screenClean: return "paintbrush.pointed.fill"
        case .lockKeyboard: return "keyboard.fill"
        case .lockScreen: return "lock.display"
        case .xcodeClean: return "hammer.fill"
        case .emptyTrash: return "trash.fill"
        case .ejectDisk: return "eject.fill"
        case .emptyPasteboard: return "doc.on.clipboard"
        case .hideWindows: return "macwindow.on.rectangle"
        case .hideDock: return "dock.rectangle"
        case .lowPowerMode: return "battery.25percent"
        case .energyMode: return "bolt.circle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .stageManager: return Color(red: 0.98, green: 0.38, blue: 0.15)
        case .hideWidgets: return Color(red: 0.20, green: 0.53, blue: 0.92)
        case .muteMicrophone: return Color(red: 0.94, green: 0.16, blue: 0.22)
        case .hideDesktopIcons: return Color(red: 0.22, green: 0.49, blue: 0.95)
        case .darkMode: return Color(red: 0.34, green: 0.31, blue: 0.86)
        case .keepAwake: return Color(red: 0.95, green: 0.50, blue: 0.12)
        case .screenSaver: return Color(red: 0.58, green: 0.28, blue: 0.84)
        case .bluetoothAudio: return Color(red: 0.15, green: 0.49, blue: 0.95)
        case .doNotDisturb: return Color(red: 0.47, green: 0.39, blue: 0.88)
        case .nightShift: return Color(red: 0.98, green: 0.70, blue: 0.15)
        case .trueTone: return Color(red: 0.98, green: 0.54, blue: 0.12)
        case .playMusic: return Color(red: 0.98, green: 0.18, blue: 0.42)
        case .showHiddenFiles: return Color(red: 0.20, green: 0.60, blue: 0.74)
        case .displaySleep: return Color(red: 0.32, green: 0.44, blue: 0.74)
        case .screenResolution: return Color(red: 0.28, green: 0.44, blue: 0.92)
        case .screenClean: return Color(red: 0.03, green: 0.62, blue: 0.65)
        case .lockKeyboard: return Color(red: 0.20, green: 0.62, blue: 0.93)
        case .lockScreen: return Color(red: 0.26, green: 0.33, blue: 0.47)
        case .xcodeClean: return Color(red: 0.95, green: 0.42, blue: 0.18)
        case .emptyTrash: return Color(red: 0.74, green: 0.28, blue: 0.30)
        case .ejectDisk: return Color(red: 0.28, green: 0.42, blue: 0.72)
        case .emptyPasteboard: return Color(red: 0.46, green: 0.45, blue: 0.68)
        case .hideWindows: return Color(red: 0.26, green: 0.49, blue: 0.76)
        case .hideDock: return Color(red: 0.23, green: 0.60, blue: 0.72)
        case .lowPowerMode: return Color(red: 0.24, green: 0.66, blue: 0.32)
        case .energyMode: return Color(red: 0.98, green: 0.58, blue: 0.10)
        }
    }

}

struct PreferencesView: View {
    @ObservedObject var store: SwitchStore
    @State private var tab: PreferencesTab = .general

    init(store: SwitchStore) {
        self.store = store
        _tab = State(initialValue: PreferencesTab(rawValue: store.preferredPreferencesTab) ?? .general)
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            PreferencesColors.windowVeil
                .ignoresSafeArea()

            HStack(spacing: 10) {
                PreferencesSidebar(selection: $tab, store: store)

                ZStack(alignment: .bottom) {
                    Group {
                        switch tab {
                        case .general:
                            GeneralPreferencesView(store: store)
                        case .customize:
                            CustomizePreferencesView(store: store)
                        case .about:
                            AboutPreferencesView(store: store)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let error = store.lastError {
                        PreferencesErrorBanner(message: error, store: store)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 540, minHeight: 390)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .environment(\.locale, Locale(identifier: store.effectiveLanguage.localeIdentifier))
        .onAppear {
            publishLayout(for: tab)
        }
        .onReceive(store.$preferredPreferencesTab) { rawValue in
            if let requested = PreferencesTab(rawValue: rawValue) {
                tab = requested
                publishLayout(for: requested)
            } else if rawValue == "shortcuts" {
                tab = .customize
                publishLayout(for: .customize)
            }
        }
        .onChange(of: tab) { _, newValue in
            if store.preferredPreferencesTab != newValue.rawValue {
                store.preferredPreferencesTab = newValue.rawValue
            }
            publishLayout(for: newValue)
        }
    }

    private func publishLayout(for tab: PreferencesTab) {
        NotificationCenter.default.post(
            name: .setMacSwitchPreferencesLayout,
            object: nil,
            userInfo: ["mode": "compact"]
        )
    }
}

private enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case customize
    case about

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .general: return L10n.text(.general, language: language)
        case .customize: return L10n.text(.customize, language: language)
        case .about: return L10n.text(.about, language: language)
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .customize: return "wand.and.stars"
        case .about: return "info.circle"
        }
    }

    var isImplemented: Bool {
        true
    }
}

private enum PreferencesColors {
    static let windowVeil = Color(nsColor: .windowBackgroundColor).opacity(0.10)
    static let surface = Color.primary.opacity(0.035)
    static let surfaceElevated = Color(nsColor: .controlBackgroundColor).opacity(0.34)
    static let selected = Color.accentColor.opacity(0.18)
    static let selectedStroke = Color.accentColor.opacity(0.16)
    static let border = Color.primary.opacity(0.10)
    static let separator = Color.primary.opacity(0.075)
    static let subduedFill = Color.primary.opacity(0.055)
    static let subtleText = Color.secondary.opacity(0.88)
    static let titlebarInset: CGFloat = 14
    static let glassGlow = Color.white.opacity(0.22)
}

private struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var fillOpacity: Double = 0.18

    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PreferencesColors.glassGlow.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(PreferencesColors.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat = 12, fillOpacity: Double = 0.18) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, fillOpacity: fillOpacity))
    }
}

private struct PreferencesSidebar: View {
    @Binding var selection: PreferencesTab
    @ObservedObject var store: SwitchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "switch.2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Mac Switch")
                        .font(.system(size: 13.5, weight: .bold))
                    Text(store.text(.preferences))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)

            VStack(spacing: 4) {
                ForEach(PreferencesTab.allCases) { item in
                    SidebarTabButton(item: item, title: item.title(language: store.effectiveLanguage), isSelected: selection == item) {
                        if item.isImplemented {
                            selection = item
                        }
                    }
                }
            }

            Spacer()

            Text(store.text(.menuBarUtility))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
        }
        .padding(.horizontal, 10)
        .padding(.top, PreferencesColors.titlebarInset)
        .padding(.bottom, 10)
        .frame(width: 132)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(PreferencesColors.border, lineWidth: 1)
        )
    }
}

private struct PreferencesErrorBanner: View {
    let message: String
    @ObservedObject var store: SwitchStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let remediation {
                Button {
                    ErrorFixRouter.route(message: message, store: store)
                } label: {
                    Label(remediation.title, systemImage: remediation.symbol)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                store.clearLastError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        .help(message)
    }

    private var remediation: ErrorRemediation? {
        ErrorFixRouter.remediation(for: message)
    }
}

private struct SidebarTabButton: View {
    let item: PreferencesTab
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 12.6, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Text(title)
                    .font(.system(size: 12.1, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.90)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? PreferencesColors.selected : (isHovering ? PreferencesColors.subduedFill : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? PreferencesColors.selectedStroke : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!item.isImplemented)
        .onHover { isHovering = $0 }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let scrolls: Bool
    let content: Content

    init(title: String, subtitle: String, scrolls: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.scrolls = scrolls
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11.2, weight: .regular))
                    .foregroundStyle(PreferencesColors.subtleText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, PreferencesColors.titlebarInset + 1)
            .padding(.bottom, 11)

            if scrolls {
                ScrollView {
                    content
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .frame(maxWidth: 560, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content
    @State private var isExpanded = true

    init(_ title: String, defaultExpanded: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        _isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)

                    Text(title.uppercased())
                        .font(.system(size: 10.2, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle()
                    .fill(PreferencesColors.separator)
                    .frame(height: 1)

                VStack(spacing: 0) {
                    content
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassCard(cornerRadius: 11, fillOpacity: 0.12)
        .clipped()
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(PreferencesColors.separator)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let accessory: Accessory
    @State private var isExpanded = false

    init(title: String, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    guard subtitle != nil else { return }
                    withAnimation(.snappy(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(subtitle == nil ? Color.clear : .secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 10)

                        Text(title)
                            .font(.system(size: 12.6, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                accessory
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 38)

            if isExpanded, let subtitle {
                Text(subtitle)
                    .font(.system(size: 11.3, weight: .regular))
                    .foregroundStyle(PreferencesColors.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 30)
                    .padding(.trailing, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct SettingsPill: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct GeneralPreferencesView: View {
    @ObservedObject var store: SwitchStore
    @State private var accessibilityTrusted = false
    @State private var isCheckingAccessibility = false
    @State private var pendingAccessibilityCheck = false

    var body: some View {
        SettingsPage(
            title: store.text(.general),
            subtitle: store.text(.generalSubtitle)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsGroup(store.text(.startup)) {
                    SettingsRow(
                        title: store.text(.startAtLogin)
                    ) {
                        HStack(spacing: 8) {
                            SettingsPill(
                                text: startAtLoginPillText,
                                color: startAtLoginPillColor
                            )

                            Button {
                                if reportOpenResult(
                                    SystemSettingsLinks.openLoginItems(),
                                    store: store,
                                    failureMessage: "Could not open Login Items settings."
                                ) {
                                    refreshStartAtLoginStatusSoon()
                                }
                            } label: {
                                Label(store.text(.review), systemImage: "gearshape")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(store.isUpdatingStartAtLogin)

                            if store.startAtLoginNeedsApproval {
                                Button {
                                    if reportOpenResult(
                                        SystemSettingsLinks.openLoginItems(),
                                        store: store,
                                        failureMessage: "Could not open Login Items settings."
                                    ) {
                                        refreshStartAtLoginStatusSoon()
                                    }
                                } label: {
                                    Label(store.text(.approve), systemImage: "checkmark.circle")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(store.isUpdatingStartAtLogin)

                                Button {
                                    store.cancelStartAtLoginApproval()
                                } label: {
                                    Label(store.text(.cancel), systemImage: "xmark.circle")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(store.isUpdatingStartAtLogin)
                            } else if store.startAtLoginNeedsRepair {
                                Button {
                                    store.repairStartAtLogin()
                                } label: {
                                    Label(store.text(.repair), systemImage: "wrench.and.screwdriver")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(store.isUpdatingStartAtLogin)
                            }

                            Toggle("", isOn: $store.startAtLogin)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(store.isUpdatingStartAtLogin || store.startAtLoginNeedsApproval)
                                .opacity((store.isUpdatingStartAtLogin || store.startAtLoginNeedsApproval) ? 0.65 : 1)
                                .help(store.startAtLoginNeedsApproval ? "Approve Mac Switch in Login Items to finish enabling Start at Login." : "")
                        }
                    }
                }

                SettingsGroup(store.text(.language)) {
                    SettingsRow(
                        title: store.text(.language),
                        subtitle: store.text(.languageSubtitle)
                    ) {
                        Picker("", selection: $store.appLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.pickerTitle(in: store.effectiveLanguage)).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 178)
                    }
                }

                SettingsGroup(store.text(.menuBar)) {
                    SettingsRow(
                        title: store.text(.menuBarIcon)
                    ) {
                        Picker("", selection: $store.menuBarIcon) {
                            ForEach(MenuBarIcon.allCases) { icon in
                                HStack(spacing: 8) {
                                    Image(nsImage: icon.templateImage(size: NSSize(width: 17, height: 17)))
                                        .renderingMode(.template)
                                        .frame(width: 17, height: 17)
                                    Text(store.menuBarIconTitle(icon))
                                }
                                .tag(icon)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 178)
                    }
                }

                SettingsGroup(store.text(.permissions), defaultExpanded: true) {
                    SettingsRow(
                        title: store.text(.accessibility),
                        subtitle: accessibilitySubtitle
                    ) {
                        HStack(spacing: 8) {
                            SettingsPill(
                                text: accessibilityPillText,
                                color: accessibilityPillColor
                            )
                            Button {
                                if reportOpenResult(
                                    AccessibilityPermission.requestAndOpenSettings(),
                                    store: store,
                                    failureMessage: "Could not open Accessibility settings."
                                ) {
                                    refreshPermissionStatusSoon()
                                }
                            } label: {
                                Label(store.text(.open), systemImage: "gearshape")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: store.text(.automation),
                        subtitle: store.text(.automationSubtitle)
                    ) {
                        Button {
                            reportOpenResult(
                                SystemSettingsLinks.openAutomation(),
                                store: store,
                                failureMessage: "Could not open Automation settings."
                            )
                        } label: {
                            Label(store.text(.review), systemImage: "gearshape")
                        }
                        .buttonStyle(.bordered)
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: store.text(.location),
                        subtitle: store.text(.locationSubtitle)
                    ) {
                        Button {
                            reportOpenResult(
                                SystemSettingsLinks.openLocationServices(),
                                store: store,
                                failureMessage: "Could not open Location Services settings."
                            )
                        } label: {
                            Label(store.text(.open), systemImage: "location")
                        }
                        .buttonStyle(.bordered)
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: store.text(.bluetooth),
                        subtitle: store.text(.bluetoothSubtitle)
                    ) {
                        Button {
                            reportOpenResult(
                                SystemSettingsLinks.openBluetooth(),
                                store: store,
                                failureMessage: "Could not open Bluetooth settings."
                            )
                        } label: {
                            Label(store.text(.open), systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                SettingsGroup(store.text(.application)) {
                    SettingsRow(
                        title: store.text(.quitMacSwitch)
                    ) {
                        Button {
                            store.quit()
                        } label: {
                            Label(store.text(.quit), systemImage: "power")
                        }
                        .buttonStyle(.bordered)
                    }
                }

            }
        }
        .onAppear {
            store.refreshStartAtLoginStatusAsync()
            refreshAccessibilityStatus()
        }
    }

    private func refreshPermissionStatusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            refreshDynamicStatus(forceSwitchRefresh: true)
        }
    }

    private func refreshStartAtLoginStatusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            store.refreshStartAtLoginStatusAsync()
        }
    }

    private func refreshDynamicStatus(forceSwitchRefresh: Bool = false) {
        if !store.isUpdatingStartAtLogin {
            store.refreshStartAtLoginStatusAsync()
        }
        refreshAccessibilityStatus(forceSwitchRefresh: forceSwitchRefresh)
    }

    private func refreshAccessibilityStatus(forceSwitchRefresh: Bool = false) {
        guard !isCheckingAccessibility else {
            pendingAccessibilityCheck = pendingAccessibilityCheck || forceSwitchRefresh
            return
        }
        isCheckingAccessibility = true
        DispatchQueue.global(qos: .utility).async {
            let latestAccessibilityTrusted = AccessibilityPermission.isTrusted
            DispatchQueue.main.async {
                let shouldRefreshSwitches = forceSwitchRefresh || latestAccessibilityTrusted != accessibilityTrusted
                accessibilityTrusted = latestAccessibilityTrusted
                let shouldCheckAgain = pendingAccessibilityCheck
                pendingAccessibilityCheck = false
                isCheckingAccessibility = false
                if shouldRefreshSwitches {
                    store.refreshAsync(.screenClean)
                    store.refreshAsync(.lockKeyboard)
                }
                if shouldCheckAgain {
                    refreshAccessibilityStatus(forceSwitchRefresh: true)
                }
            }
        }
    }

    private var accessibilitySubtitle: String {
        if isCheckingAccessibility && !accessibilityTrusted {
            return store.text(.checkingAccessibilitySubtitle)
        }
        return accessibilityTrusted
            ? store.text(.accessibilityGrantedSubtitle)
            : store.text(.accessibilityRequiredSubtitle)
    }

    private var accessibilityPillText: String {
        if isCheckingAccessibility && !accessibilityTrusted {
            return store.text(.checking)
        }
        return accessibilityTrusted ? store.text(.granted) : store.text(.needsAccess)
    }

    private var accessibilityPillColor: Color {
        if isCheckingAccessibility && !accessibilityTrusted {
            return .secondary
        }
        return accessibilityTrusted ? .green : .orange
    }

    private var startAtLoginPillText: String {
        if store.isUpdatingStartAtLogin {
            return store.text(.checking)
        }
        if store.startAtLoginNeedsApproval {
            return store.text(.pending)
        }
        if store.startAtLoginNeedsRepair {
            return store.text(.repair)
        }
        return store.startAtLogin ? store.text(.on) : store.text(.off)
    }

    private var startAtLoginPillColor: Color {
        if store.isUpdatingStartAtLogin {
            return .secondary
        }
        if store.startAtLoginNeedsApproval || store.startAtLoginNeedsRepair {
            return .orange
        }
        return store.startAtLogin ? .green : .secondary
    }
}

private enum AppLinks {
    static var feedback: URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "MacSwitchFeedbackURL") as? String,
              let url = URL(string: rawValue)
        else {
            return nil
        }
        return url
    }

    static let shortcutsApp = URL(fileURLWithPath: "/System/Applications/Shortcuts.app")
    static let diskUtility = URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app")
}

private enum AppDiagnostics {
    private static let refreshPollInterval: TimeInterval = 0.1
    private static let refreshPollLimit = 12

    static func copyToPasteboard(store: SwitchStore, completion: @escaping () -> Void) {
        store.refreshAllAsync()
        DispatchQueue.global(qos: .utility).async {
            let loginSummary = LoginItemManager.diagnosticSummary
            let accessibilityTrusted = AccessibilityPermission.isTrusted
            DispatchQueue.main.async {
                writeWhenRefreshSettled(
                    store: store,
                    loginSummary: loginSummary,
                    accessibilityTrusted: accessibilityTrusted,
                    remainingAttempts: refreshPollLimit,
                    completion: completion
                )
            }
        }
    }

    private static func writeWhenRefreshSettled(
        store: SwitchStore,
        loginSummary: String,
        accessibilityTrusted: Bool,
        remainingAttempts: Int,
        completion: @escaping () -> Void
    ) {
        guard store.isRefreshing && remainingAttempts > 0 else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                summary(store: store, loginSummary: loginSummary, accessibilityTrusted: accessibilityTrusted),
                forType: .string
            )
            store.refreshAsync(.emptyPasteboard)
            completion()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + refreshPollInterval) {
            writeWhenRefreshSettled(
                store: store,
                loginSummary: loginSummary,
                accessibilityTrusted: accessibilityTrusted,
                remainingAttempts: remainingAttempts - 1,
                completion: completion
            )
        }
    }

    static func summary(store: SwitchStore, loginSummary: String, accessibilityTrusted: Bool) -> String {
        let processInfo = ProcessInfo.processInfo
        let os = processInfo.operatingSystemVersion
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let capturedAt = ISO8601DateFormatter().string(from: Date())
        let actions = (
            store.actionsInProgress.map(\.title) +
            store.actionsPreparing.map { "Preparing \($0.title)" }
        ).sorted()
        let switchLines = SwitchKind.allCases.map { kind -> String in
            let snapshot = store.snapshots[kind] ?? .off
            let status = snapshot.isAvailable ? (snapshot.isOn ? "on" : "off") : "unavailable"
            let detail = DiagnosticRedactor.redact(snapshot.warning ?? snapshot.subtitle ?? "")
            return "- \(kind.title): \(status)\(detail.isEmpty ? "" : " (\(detail))")"
        }
        let lastError = store.lastError.map(DiagnosticRedactor.redact) ?? "none"
        let appPath = DiagnosticRedactor.redact(Bundle.main.bundleURL.path)
        let executablePath = DiagnosticRedactor.redact(Bundle.main.executablePath ?? "-")

        return """
        Mac Switch \(version) (\(build))
        Captured: \(capturedAt)
        macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
        Start at Login: \(store.startAtLogin ? "on" : "off")
        Login item: \(loginSummary)
        Accessibility trusted: \(accessibilityTrusted ? "yes" : "no")
        Location: \(store.darkModeLocationStatus)
        Snapshot refresh requested before copy: yes
        Refresh in progress: \(store.isRefreshing ? "yes" : "no")
        Actions in progress: \(actions.isEmpty ? "none" : actions.joined(separator: ", "))
        Last error: \(lastError)
        App path: \(appPath)
        Executable: \(executablePath)
        Visible switches: \(store.visibleKinds.count)

        Switch status:
        \(switchLines.joined(separator: "\n"))
        """
    }
}

private struct SwitchShortcutSection: View {
    let kind: SwitchKind
    @ObservedObject var store: SwitchStore

    private var snapshot: SwitchSnapshot {
        store.snapshots[kind] ?? .off
    }

    private var helperText: (text: String, color: Color)? {
        if let shortcut = store.shortcuts[kind],
           let owner = store.shortcutOwner(for: shortcut, excluding: kind) {
            return ("Already used by \(owner.title)", .red)
        }
        if !snapshot.isAvailable {
            return (snapshot.warning ?? "Unavailable on this Mac", .orange)
        }
        if !store.enabledKinds.contains(kind), store.shortcuts[kind] != nil {
            return ("Hidden from dashboard; shortcut still works", .secondary)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "keyboard")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 13.5, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text("Shortcut")
                    .font(.system(size: 12.4, weight: .semibold))
                    .lineLimit(1)

                Spacer()
            }

            HStack(spacing: 8) {
                ShortcutRecorderButton(shortcut: store.shortcuts[kind]) { shortcut in
                    store.setShortcut(kind, shortcut: shortcut)
                }
                .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)

                Button {
                    store.setShortcut(kind, shortcut: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .disabled(store.shortcuts[kind] == nil)
                .opacity(store.shortcuts[kind] == nil ? 0.28 : 1)
                .help("Clear shortcut")
            }

            Text("Two modifiers + key. Delete clears.")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(PreferencesColors.subtleText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if let helperText {
                Label(helperText.text, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(helperText.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(10)
        .background(PreferencesColors.subduedFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct ShortcutRecorderButton: NSViewRepresentable {
    let shortcut: HotKeyShortcut?
    let onRecord: (HotKeyShortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButtonView {
        let view = ShortcutRecorderButtonView(frame: .zero)
        view.onRecord = onRecord
        view.shortcut = shortcut
        view.updateTitle()
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderButtonView, context: Context) {
        nsView.onRecord = onRecord
        nsView.shortcut = shortcut
        nsView.updateTitle()
    }
}

private final class ShortcutRecorderButtonView: NSButton {
    var shortcut: HotKeyShortcut?
    var onRecord: ((HotKeyShortcut?) -> Void)?
    private var recording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        controlSize = .small
        font = NSFont.systemFont(ofSize: 12, weight: .regular)
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
        focusRingType = .default
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        recording = true
        window?.makeFirstResponder(self)
        updateTitle()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 53:
            recording = false
            window?.makeFirstResponder(nil)
            updateTitle()
        case 51, 117:
            shortcut = nil
            onRecord?(nil)
            recording = false
            window?.makeFirstResponder(nil)
            updateTitle()
        default:
            let modifiers = HotKeyShortcut.carbonModifiers(from: event.modifierFlags)
            guard HotKeyShortcut.isValidGlobalShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers) else {
                title = HotKeyShortcut.recordingFailureTitle(keyCode: UInt32(event.keyCode), modifiers: modifiers)
                NSSound.beep()
                return
            }

            let newShortcut = HotKeyShortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: modifiers,
                display: HotKeyShortcut.displayText(for: event, modifiers: modifiers)
            )
            shortcut = newShortcut
            onRecord?(newShortcut)
            recording = false
            window?.makeFirstResponder(nil)
            updateTitle()
        }
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    func updateTitle() {
        if recording {
            title = "Type shortcut..."
        } else {
            title = shortcut?.display ?? "Record Shortcut"
        }
    }
}

private struct AboutPreferencesView: View {
    @ObservedObject var store: SwitchStore
    @ObservedObject private var softwareUpdates = SoftwareUpdateManager.shared
    @State private var diagnosticsCopied = false
    @State private var diagnosticsCopyInProgress = false
    @State private var confirmsClearingShortcuts = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    var body: some View {
        SettingsPage(
            title: store.text(.about),
            subtitle: "Mac Switch is a compact native switchboard for everyday system controls."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "switch.2")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 48, height: 48)
                        .background(PreferencesColors.subduedFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mac Switch")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Version \(version) (\(build))")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("A menu bar utility designed for fast, low-friction control over display, focus, power, input, and cleanup workflows.")
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundStyle(PreferencesColors.subtleText)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                SettingsGroup("Updates") {
                    SettingsRow(
                        title: "Check for Updates",
                        subtitle: updateCheckSubtitle
                    ) {
                        HStack(spacing: 8) {
                            SettingsPill(
                                text: softwareUpdates.isAvailable ? "Ready" : "Unavailable",
                                color: softwareUpdates.isAvailable ? .green : .secondary
                            )

                            Button {
                                softwareUpdates.checkForUpdates()
                            } label: {
                                Label("Check", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!softwareUpdates.canCheckForUpdates)
                        }
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Automatically Check"
                    ) {
                        Toggle("", isOn: $softwareUpdates.automaticallyChecksForUpdates)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(!softwareUpdates.isAvailable)
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Download Updates in Background"
                    ) {
                        Toggle("", isOn: $softwareUpdates.automaticallyDownloadsUpdates)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(!softwareUpdates.isAvailable || !softwareUpdates.automaticallyChecksForUpdates)
                    }
                }

                SettingsGroup("Resources") {
                    SettingsRow(title: "App Bundle", subtitle: "Reveal the currently running Mac Switch app in Finder.") {
                        Button {
                            reportOpenResult(
                                revealInFinder(Bundle.main.bundleURL),
                                store: store,
                                failureMessage: "Could not reveal the Mac Switch app bundle."
                            )
                        } label: {
                            Label("Reveal", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }

                    SettingsDivider()

                    SettingsRow(title: "Feedback", subtitle: "File a bug report or feature request on GitHub.") {
                        Button {
                            if let feedback = AppLinks.feedback {
                                openWorkspaceURLOrReport(
                                    feedback,
                                    store: store,
                                    failureMessage: "Could not open GitHub issues."
                                )
                            } else {
                                store.lastError = "Feedback URL is not configured for this build."
                            }
                        } label: {
                            Label("Issue", systemImage: "exclamationmark.bubble")
                        }
                        .buttonStyle(.bordered)
                    }

                    SettingsDivider()

                    SettingsRow(title: "Diagnostics", subtitle: "Copy a short technical summary for support.") {
                        Button {
                            copyDiagnostics()
                        } label: {
                            Label(
                                diagnosticsButtonTitle,
                                systemImage: diagnosticsCopied ? "checkmark" : "doc.on.doc"
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(diagnosticsCopyInProgress)
                    }

                    SettingsDivider()

                    SettingsRow(title: "Shortcuts", subtitle: "Remove every global shortcut assignment.") {
                        Button {
                            confirmsClearingShortcuts = true
                        } label: {
                            Label("Clear All", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.shortcuts.isEmpty)
                        .confirmationDialog(
                            "Clear all shortcuts?",
                            isPresented: $confirmsClearingShortcuts,
                            titleVisibility: .visible
                        ) {
                            Button("Clear All Shortcuts", role: .destructive) {
                                store.clearAllShortcuts()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This removes every global shortcut assignment.")
                        }
                    }
                }
            }
        }
        .onAppear {
            softwareUpdates.refresh()
        }
    }

    private func showDiagnosticsCopied() {
        diagnosticsCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            diagnosticsCopied = false
        }
    }

    private var diagnosticsButtonTitle: String {
        if diagnosticsCopyInProgress {
            return "Copying"
        }
        return diagnosticsCopied ? "Copied" : "Copy"
    }

    private var updateCheckSubtitle: String {
        guard softwareUpdates.isAvailable else {
            return "Available in the signed app bundle."
        }
        if let lastUpdateCheckDate = softwareUpdates.lastUpdateCheckDate {
            return "Last checked \(lastUpdateCheckDate.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Check the official release feed for a newer notarized build."
    }

    private func copyDiagnostics() {
        guard !diagnosticsCopyInProgress else { return }
        diagnosticsCopyInProgress = true
        AppDiagnostics.copyToPasteboard(store: store) {
            diagnosticsCopyInProgress = false
            showDiagnosticsCopied()
        }
    }
}

private struct CustomizePreferencesView: View {
    @ObservedObject var store: SwitchStore
    @State private var selectedKind: SwitchKind?
    @State private var didInitializeSelection = false

    init(store: SwitchStore) {
        self.store = store
        _selectedKind = State(initialValue: Self.initialSelection(in: store))
    }

    private var enabledCount: Int {
        store.orderedKinds.filter { store.enabledKinds.contains($0) }.count
    }

    private var sortedKinds: [SwitchKind] {
        store.orderedKinds.sorted { lhs, rhs in
            let lhsEnabled = store.enabledKinds.contains(lhs)
            let rhsEnabled = store.enabledKinds.contains(rhs)
            if lhsEnabled != rhsEnabled {
                return lhsEnabled && !rhsEnabled
            }

            let titleOrder = store.switchTitle(lhs).localizedStandardCompare(store.switchTitle(rhs))
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }

            return lhs.rawValue < rhs.rawValue
        }
    }

    var body: some View {
        SettingsPage(
            title: store.text(.customize),
            subtitle: "Choose which switches appear in the menu.",
            scrolls: false
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SettingsPill(text: "\(enabledCount) visible", color: Color.accentColor)
                    Text("Drag items in the menu bar menu to change order.")
                        .font(.system(size: 11.8, weight: .medium))
                        .foregroundStyle(PreferencesColors.subtleText)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        store.resetCustomization()
                        closeDetailPanel()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.hasBusyActions)
                    .help("Restore the default switch order and visible switches.")
                }

                GeometryReader { proxy in
                    HStack(alignment: .top, spacing: selectedKind == nil ? 0 : 10) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Dashboard Switches")
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(store.orderedKinds.count) total")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(PreferencesColors.surface)

                            Divider()

                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(sortedKinds) { kind in
                                        CustomizeRow(
                                            kind: kind,
                                            title: store.switchTitle(kind),
                                            isSelected: selectedKind == kind,
                                            isEnabled: store.enabledKinds.contains(kind),
                                            isBusy: store.isCustomizationBusy(kind),
                                            statusText: store.customizationStatusText(for: kind),
                                            setEnabled: { store.setEnabled(kind, $0) },
                                            openOptions: {
                                                toggleDetailPanel(for: kind)
                                            }
                                        )
                                            .contentShape(Rectangle())

                                        if kind != sortedKinds.last {
                                            SettingsDivider()
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glassCard(cornerRadius: 11, fillOpacity: 0.10)

                        if let selectedKind {
                            SwitchPreferencePanel(
                                kind: selectedKind,
                                store: store,
                                onClose: {
                                    closeDetailPanel()
                                }
                            )
                                .frame(width: min(360, max(330, proxy.size.width * 0.36)))
                                .frame(maxHeight: .infinity)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .zIndex(2)
                        }
                    }
                    .animation(.snappy(duration: 0.24), value: selectedKind)
                }
            }
        }
        .onAppear {
            applyRequestedSelectionIfNeeded()
            reconcileSelectionIfNeeded()
            publishCustomizeLayout(detailVisible: selectedKind != nil)
        }
        .onReceive(store.$preferredCustomizeKind) { _ in
            applyRequestedSelectionIfNeeded()
        }
        .onDisappear {
            selectedKind = nil
            publishCustomizeLayout(detailVisible: false)
        }
    }

    private static func initialSelection(in store: SwitchStore) -> SwitchKind? {
        store.preferredCustomizeKind
    }

    private func applyRequestedSelectionIfNeeded() {
        guard let requested = store.preferredCustomizeKind,
              store.orderedKinds.contains(requested)
        else { return }
        openDetailPanel(for: requested)
        didInitializeSelection = true
        DispatchQueue.main.async {
            if store.preferredCustomizeKind == requested {
                store.preferredCustomizeKind = nil
            }
        }
    }

    private func reconcileSelectionIfNeeded() {
        if !didInitializeSelection {
            didInitializeSelection = true
        } else if let selectedKind, !store.orderedKinds.contains(selectedKind) {
            closeDetailPanel()
        }
    }

    private func toggleDetailPanel(for kind: SwitchKind) {
        if selectedKind == kind {
            closeDetailPanel()
        } else {
            openDetailPanel(for: kind)
        }
    }

    private func openDetailPanel(for kind: SwitchKind) {
        publishCustomizeLayout(detailVisible: true)
        withAnimation(.snappy(duration: 0.24)) {
            selectedKind = kind
        }
    }

    private func closeDetailPanel() {
        withAnimation(.snappy(duration: 0.20)) {
            selectedKind = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if selectedKind == nil {
                publishCustomizeLayout(detailVisible: false)
            }
        }
    }

    private func publishCustomizeLayout(detailVisible: Bool) {
        NotificationCenter.default.post(
            name: .setMacSwitchPreferencesLayout,
            object: nil,
            userInfo: ["mode": detailVisible ? "detail" : "compact"]
        )
    }
}

private struct CustomizeRow: View {
    let kind: SwitchKind
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let isBusy: Bool
    let statusText: String
    let setEnabled: (Bool) -> Void
    let openOptions: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: setEnabled
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 20)
            .disabled(isBusy)

            Button(action: openOptions) {
                HStack(spacing: 10) {
                    Image(systemName: kind.modernSymbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(kind.accentColor)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12.7, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(statusText)
                            .font(.system(size: 10.8, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor.opacity(0.82) : Color.secondary.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .frame(height: Self.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? PreferencesColors.selected : Color.clear)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
        )
    }

    fileprivate static let rowHeight: CGFloat = 46
}

private struct SwitchPreferencePanel: View {
    let kind: SwitchKind
    @ObservedObject var store: SwitchStore
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 10) {
                    if let onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 22, height: 22)
                                .background(PreferencesColors.subduedFill, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Close switch preferences")
                    }

                    Image(systemName: kind.modernSymbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(kind.accentColor)
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 26, height: 26)

                    SettingsPill(
                        text: store.isCustomizationBusy(kind)
                            ? "Updating"
                            : (store.enabledKinds.contains(kind) ? "Visible" : "Hidden"),
                        color: store.isCustomizationBusy(kind)
                            ? Color.orange
                            : (store.enabledKinds.contains(kind) ? Color.accentColor : Color.secondary)
                    )

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.switchTitle(kind))
                        .font(.system(size: 15.5, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                    Text("Switch preferences")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        switch kind {
                        case .bluetoothAudio:
                            BluetoothAudioPreferencesPanel(store: store)
                        case .screenResolution:
                            ScreenResolutionPreferencesPanel(store: store)
                        case .doNotDisturb:
                            DoNotDisturbPreferencesPanel(store: store)
                        case .darkMode:
                            DarkModePreferencesPanel(store: store)
                        case .nightShift:
                            NightShiftPreferencesPanel(store: store)
                        case .keepAwake:
                            KeepAwakePreferencesPanel(store: store)
                        case .playMusic:
                            PlayMusicPreferencesPanel(store: store)
                        case .screenClean, .lockKeyboard:
                            AccessibilityPreferencesPanel(kind: kind, store: store)
                        case .muteMicrophone:
                            MicrophonePreferencesPanel(store: store)
                        case .stageManager, .hideWidgets, .hideDesktopIcons, .showHiddenFiles, .hideDock:
                            DesktopDockPreferencesPanel(kind: kind, store: store)
                        case .screenSaver, .lockScreen:
                            LockScreenPreferencesPanel(kind: kind, store: store)
                        case .displaySleep, .trueTone:
                            DisplayUtilityPreferencesPanel(kind: kind, store: store)
                        case .lowPowerMode:
                            LowPowerModePreferencesPanel(store: store)
                        case .emptyTrash:
                            TrashPreferencesPanel(store: store)
                        case .emptyPasteboard:
                            PasteboardPreferencesPanel(store: store)
                        case .hideWindows:
                            HideWindowsPreferencesPanel(store: store)
                        case .ejectDisk:
                            EjectDiskPreferencesPanel(store: store)
                        case .xcodeClean:
                            XcodeCleanPreferencesPanel(store: store)
                        case .energyMode:
                            EnergyModePreferencesPanel(store: store)
                        }
                    }

                    Divider()

                    SwitchShortcutSection(kind: kind, store: store)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .controlSize(.small)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(cornerRadius: 11, fillOpacity: 0.10)
    }
}

private struct BluetoothAudioPreferencesPanel: View {
    @ObservedObject var store: SwitchStore
    @State private var selectedAddress = BluetoothAudioPreferences.selectedAddress
    @State private var devices: [BluetoothAudioDeviceOption] = []
    @State private var bluetoothPoweredOn = true
    @State private var isRefreshingDevices = false
    @State private var pendingDeviceRefresh = false
    @State private var pendingResetMissingSelection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose the Bluetooth audio device Mac Switch connects from the dashboard.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            if isRefreshingDevices && devices.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking paired audio devices...")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else if !bluetoothPoweredOn {
                Text("Please turn on Bluetooth.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openBluetooth(),
                        store: store,
                        failureMessage: "Could not open Bluetooth settings."
                    )
                } label: {
                    Label("Open Bluetooth Settings", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)
            } else if devices.isEmpty {
                Text("No paired Bluetooth audio devices found.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openBluetooth(),
                        store: store,
                        failureMessage: "Could not open Bluetooth settings."
                    )
                } label: {
                    Label("Pair Audio Device", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            } else {
                if selectedDeviceMissing {
                    RecoveryNotice(
                        symbol: "headphones",
                        title: "Selected device is no longer paired",
                        message: "Mac Switch will not connect a different device until you choose one or reset to Automatic."
                    ) {
                        selectedAddress = ""
                        BluetoothAudioPreferences.selectedAddress = ""
                        reloadDevices(resetMissingSelection: true)
                    }
                }

                Picker("Device:", selection: $selectedAddress) {
                    Text("Automatic").tag("")
                    ForEach(devices) { device in
                        Text(device.name + (device.isConnected ? " - connected" : ""))
                            .tag(device.address)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRefreshingDevices || store.isActionBusy(.bluetoothAudio))
                .onChange(of: selectedAddress) { _, value in
                    BluetoothAudioPreferences.selectedAddress = value
                    store.refreshAsync(.bluetoothAudio)
                }
            }

            HStack(spacing: 10) {
                Button {
                    reloadDevices(resetMissingSelection: false)
                } label: {
                    Label(isRefreshingDevices ? "Checking..." : "Refresh Devices", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshingDevices || store.isActionBusy(.bluetoothAudio))

                if selectedDeviceMissing {
                    Button {
                        selectedAddress = ""
                        BluetoothAudioPreferences.selectedAddress = ""
                        reloadDevices(resetMissingSelection: true)
                    } label: {
                        Label("Use Automatic", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRefreshingDevices || store.isActionBusy(.bluetoothAudio))
                }
            }
        }
        .onAppear {
            selectedAddress = BluetoothAudioPreferences.selectedAddress
            reloadDevices(resetMissingSelection: false)
        }
        .onReceive(Timer.publish(every: 6, on: .main, in: .common).autoconnect()) { _ in
            reloadDevices(resetMissingSelection: false)
        }
    }

    private var selectedDeviceMissing: Bool {
        let normalized = BluetoothAudioPreferences.selectedAddress
        return !normalized.isEmpty && !devices.contains {
            $0.address.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    private func reloadDevices(resetMissingSelection: Bool) {
        guard !isRefreshingDevices else {
            pendingDeviceRefresh = true
            pendingResetMissingSelection = pendingResetMissingSelection || resetMissingSelection
            return
        }
        isRefreshingDevices = true
        let shouldResetMissingSelection = resetMissingSelection

        DispatchQueue.global(qos: .utility).async {
            let poweredOn = BluetoothAudioPreferences.bluetoothPoweredOn
            let refreshedDevices = poweredOn ? BluetoothAudioPreferences.deviceOptions : []

            DispatchQueue.main.async {
                let latestAddress = BluetoothAudioPreferences.selectedAddress
                bluetoothPoweredOn = poweredOn
                devices = refreshedDevices

                if shouldResetMissingSelection,
                   !latestAddress.isEmpty,
                   !refreshedDevices.contains(where: { $0.address.caseInsensitiveCompare(latestAddress) == .orderedSame }) {
                    selectedAddress = ""
                    BluetoothAudioPreferences.selectedAddress = ""
                } else if selectedAddress != latestAddress {
                    selectedAddress = latestAddress
                }

                let shouldRefreshAgain = pendingDeviceRefresh
                let shouldResetAgain = pendingResetMissingSelection
                pendingDeviceRefresh = false
                pendingResetMissingSelection = false
                isRefreshingDevices = false
                store.refreshAsync(.bluetoothAudio)

                if shouldRefreshAgain {
                    reloadDevices(resetMissingSelection: shouldResetAgain)
                }
            }
        }
    }
}

private struct RecoveryNotice: View {
    let symbol: String
    let title: String
    let message: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .bold))
                Text(message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Fix") {
                action()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(11)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.orange.opacity(0.20), lineWidth: 1)
        )
    }
}

private struct StatusSummaryRow: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ConfirmationToggle: View {
    let kind: SwitchKind
    let title: String
    @State private var required: Bool

    init(kind: SwitchKind, title: String) {
        self.kind = kind
        self.title = title
        _required = State(initialValue: ActionSafetyPreferences.confirmationRequired(for: kind))
    }

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { required },
            set: { value in
                required = value
                ActionSafetyPreferences.setConfirmationRequired(value, for: kind)
            }
        ))
        .toggleStyle(.checkbox)
        .onAppear {
            required = ActionSafetyPreferences.confirmationRequired(for: kind)
        }
    }
}

private struct ScreenResolutionPreferencesPanel: View {
    @ObservedObject var store: SwitchStore
    @State private var displays: [DisplayOption] = []
    @State private var selectedDisplayIndex = 0
    @State private var onlyHiDPI = ScreenResolutionPreferences.onlyHiDPI
    @State private var selectedModeID = 0
    @State private var modes: [DisplayModeOption] = []
    @State private var currentResolutionText = "Checking..."
    @State private var isRefreshingDisplays = false
    @State private var pendingDisplayRefresh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if displays.isEmpty && isRefreshingDisplays {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking displays...")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else if displays.isEmpty {
                RecoveryNotice(
                    symbol: "display.trianglebadge.exclamationmark",
                    title: "No active display found",
                    message: "macOS did not return an online display list. Open Displays or refresh after reconnecting a display."
                ) {
                    reportOpenResult(
                        SystemSettingsLinks.openDisplays(),
                        store: store,
                        failureMessage: "Could not open Displays settings."
                    )
                }
            } else {
                Picker("Display:", selection: $selectedDisplayIndex) {
                    ForEach(displays) { display in
                        Text(display.title).tag(display.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedDisplayIndex) { _, value in
                    ScreenResolutionPreferences.setSelectedDisplayIndex(value, in: displays)
                    reloadDisplays()
                    store.refreshAsync(.screenResolution)
                }
                .disabled(isRefreshingDisplays || store.isActionBusy(.screenResolution))

                Toggle("Only show HiDPI modes", isOn: $onlyHiDPI)
                    .toggleStyle(.checkbox)
                    .onChange(of: onlyHiDPI) { _, value in
                        ScreenResolutionPreferences.onlyHiDPI = value
                        reloadDisplays()
                        store.refreshAsync(.screenResolution)
                    }
                    .disabled(isRefreshingDisplays || store.isActionBusy(.screenResolution))

                Picker("Resolution:", selection: $selectedModeID) {
                    Text("Auto lower resolution").tag(0)
                    ForEach(modes) { mode in
                        Text(mode.title).tag(mode.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedModeID) { _, value in
                    ScreenResolutionPreferences.setSelectedModeID(value, for: selectedDisplay?.displayID)
                    store.refreshAsync(.screenResolution)
                }
                .disabled(isRefreshingDisplays || store.isActionBusy(.screenResolution))

                if modes.isEmpty {
                    Text("No usable target modes were reported for this display. Turn off the HiDPI filter or open Displays.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Current: \(currentResolutionText)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    reloadDisplays()
                } label: {
                    Label(isRefreshingDisplays ? "Checking..." : "Refresh Displays", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshingDisplays || store.isActionBusy(.screenResolution))

                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openDisplays(),
                        store: store,
                        failureMessage: "Could not open Displays settings."
                    )
                } label: {
                    Label("Display Settings", systemImage: "display")
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            reloadDisplays()
        }
    }

    private var selectedDisplay: DisplayOption? {
        displays.first { $0.id == selectedDisplayIndex } ?? displays.first
    }

    private func reloadDisplays() {
        guard !isRefreshingDisplays else {
            pendingDisplayRefresh = true
            return
        }
        isRefreshingDisplays = true
        currentResolutionText = "Checking..."

        DispatchQueue.global(qos: .utility).async {
            let refreshedDisplays = ScreenResolutionPreferences.displayOptions
            let refreshedDisplayIndex = ScreenResolutionPreferences.selectedDisplayIndex(in: refreshedDisplays)
            let refreshedOnlyHiDPI = ScreenResolutionPreferences.onlyHiDPI
            let selectedDisplay = refreshedDisplays.indices.contains(refreshedDisplayIndex)
                ? refreshedDisplays[refreshedDisplayIndex]
                : refreshedDisplays.first
            let refreshedModes = selectedDisplay.map {
                ScreenResolutionPreferences.modeOptions(for: $0.displayID, onlyHiDPI: refreshedOnlyHiDPI)
            } ?? []
            var refreshedModeID = ScreenResolutionPreferences.selectedModeID(for: selectedDisplay?.displayID)
            if refreshedModeID != 0,
               !refreshedModes.contains(where: { $0.id == refreshedModeID }) {
                refreshedModeID = 0
                ScreenResolutionPreferences.setSelectedModeID(0, for: selectedDisplay?.displayID)
            }
            let currentText: String
            if let selectedDisplay,
               let currentModeTitle = ScreenResolutionPreferences.currentModeTitle(for: selectedDisplay.displayID) {
                currentText = "\(selectedDisplay.title): \(currentModeTitle)"
            } else {
                currentText = "Unknown"
            }

            DispatchQueue.main.async {
                displays = refreshedDisplays
                selectedDisplayIndex = refreshedDisplayIndex
                onlyHiDPI = refreshedOnlyHiDPI
                selectedModeID = refreshedModeID
                modes = refreshedModes
                currentResolutionText = currentText

                let shouldRefreshAgain = pendingDisplayRefresh
                pendingDisplayRefresh = false
                isRefreshingDisplays = false
                store.refreshAsync(.screenResolution)

                if shouldRefreshAgain {
                    reloadDisplays()
                }
            }
        }
    }
}

private struct DoNotDisturbPreferencesPanel: View {
    @ObservedObject var store: SwitchStore
    @State private var onInstalled = false
    @State private var offInstalled = false
    @State private var isRefreshing = false
    @State private var pendingRefresh = false
    @State private var statusText = "Checking shortcut installation..."
    @State private var statusIsError = false
    @State private var hasDistinctShortcutPair = false
    @State private var onShortcutName = DoNotDisturbPreferences.customOnShortcutName
    @State private var offShortcutName = DoNotDisturbPreferences.customOffShortcutName
    @State private var shortcutNameRefreshWorkItem: DispatchWorkItem?

    private var allInstalled: Bool {
        onInstalled && offInstalled && hasDistinctShortcutPair
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Default activation duration:")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Picker("", selection: $store.doNotDisturbDuration) {
                ForEach(DoNotDisturbDuration.allCases) { duration in
                    Text(duration.menuTitle).tag(duration)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(store.isActionBusy(.doNotDisturb))

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Focus Shortcuts")
                    .font(.system(size: 15, weight: .semibold))

                Text("Create Focus on/off shortcuts in Shortcuts, then enter the exact names here.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("On shortcut name", text: $onShortcutName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: onShortcutName) { _, value in
                        DoNotDisturbPreferences.customOnShortcutName = value
                        scheduleShortcutNameRefresh()
                    }

                TextField("Off shortcut name", text: $offShortcutName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: offShortcutName) { _, value in
                        DoNotDisturbPreferences.customOffShortcutName = value
                        scheduleShortcutNameRefresh()
                    }
            }
            .disabled(isRefreshing || store.isActionBusy(.doNotDisturb))

            ShortcutInstallRow(
                title: "DND On",
                installed: onInstalled,
                store: store,
                isDisabled: store.isActionBusy(.doNotDisturb)
            )

            ShortcutInstallRow(
                title: "DND Off",
                installed: offInstalled,
                store: store,
                isDisabled: store.isActionBusy(.doNotDisturb)
            )

            HStack(spacing: 10) {
                Button(isRefreshing ? "Checking..." : "Refresh Status") {
                    refreshStatus(force: true)
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing || store.isActionBusy(.doNotDisturb))

                Spacer()

                Button(allInstalled ? "Ready" : "Continue") {
                    refreshStatus(force: true)
                    store.refreshAsync(.doNotDisturb)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allInstalled || isRefreshing || store.isActionBusy(.doNotDisturb))
            }

            HStack(spacing: 10) {
                Button {
                    openWorkspaceURLOrReport(
                        AppLinks.shortcutsApp,
                        store: store,
                        failureMessage: "Could not open Shortcuts."
                    )
                } label: {
                    Label("Open Shortcuts", systemImage: "square.stack")
                }
                .buttonStyle(.bordered)

                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openAutomation(),
                        store: store,
                        failureMessage: "Could not open Automation settings."
                    )
                } label: {
                    Label("Review Automation", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }

            Text(statusText)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(statusIsError ? Color.red : (allInstalled ? Color.green : Color.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            onShortcutName = DoNotDisturbPreferences.customOnShortcutName
            offShortcutName = DoNotDisturbPreferences.customOffShortcutName
            refreshStatus(force: true)
        }
        .onDisappear {
            shortcutNameRefreshWorkItem?.cancel()
            shortcutNameRefreshWorkItem = nil
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refreshStatus()
        }
    }

    private func scheduleShortcutNameRefresh() {
        shortcutNameRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            refreshStatus(force: true)
        }
        shortcutNameRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func refreshStatus(force: Bool = false) {
        guard !isRefreshing else {
            pendingRefresh = true
            return
        }
        isRefreshing = true
        DispatchQueue.global(qos: .utility).async {
            let installed = force
                ? DoNotDisturbPreferences.refreshInstalledShortcuts()
                : DoNotDisturbPreferences.installedShortcuts
            let shortcutError = DoNotDisturbPreferences.installedShortcutsError
            let configurationError = DoNotDisturbPreferences.shortcutConfigurationError
            let shortcutPair = DoNotDisturbPreferences.installedShortcutPair(in: installed)
            let distinctPair = shortcutPair != nil
            let on = DoNotDisturbPreferences.installedShortcutName(
                matching: DoNotDisturbPreferences.onShortcutCandidates,
                in: installed
            ) != nil
            let off = DoNotDisturbPreferences.installedShortcutName(
                matching: DoNotDisturbPreferences.offShortcutCandidates,
                in: installed
            ) != nil

            DispatchQueue.main.async {
                onInstalled = on
                offInstalled = off
                hasDistinctShortcutPair = distinctPair
                statusIsError = configurationError != nil || shortcutError != nil || (on && off && !distinctPair)
                if let configurationError {
                    statusText = configurationError
                } else if let shortcutError {
                    statusText = "Could not read Shortcuts: \(shortcutError)"
                } else if let shortcutPair {
                    statusText = "Ready. Using \(shortcutPair.on) and \(shortcutPair.off)."
                } else if on && off {
                    statusText = "DND On and DND Off must resolve to two different shortcuts."
                } else if on {
                    statusText = "DND On is installed. Install DND Off to complete setup."
                } else if off {
                    statusText = "DND Off is installed. Install DND On to complete setup."
                } else {
                    statusText = "Waiting for both shortcuts to be installed."
                }
                isRefreshing = false
                if pendingRefresh {
                    pendingRefresh = false
                    refreshStatus(force: true)
                }
                store.refreshAsync(.doNotDisturb)
            }
        }
    }
}

private struct ShortcutInstallRow: View {
    let title: String
    let installed: Bool
    @ObservedObject var store: SwitchStore
    var isDisabled = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(installed ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                Text(installed ? "Installed" : "Create or choose in Shortcuts")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Shortcuts") {
                openWorkspaceURLOrReport(
                    AppLinks.shortcutsApp,
                    store: store,
                    failureMessage: "Could not open Shortcuts."
                )
            }
            .buttonStyle(.bordered)
            .disabled(isDisabled)
        }
    }
}

private struct KeepAwakePreferencesPanel: View {
    @ObservedObject var store: SwitchStore
    @State private var keepAwakeWhenLidClosed = KeepAwakePreferences.keepAwakeWhenLidClosed
    @State private var sleepDisabled = false
    @State private var sleepStatusLoading = false
    @State private var pendingSleepStatusRefresh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusSummaryRow(
                symbol: "cup.and.saucer.fill",
                title: store.snapshots[.keepAwake]?.isOn == true ? "Keep Awake active" : "Keep Awake ready",
                message: keepAwakeWhenLidClosed
                    ? sleepStatusMessage
                    : "Keep Awake prevents idle sleep for the selected duration."
            )

            Text("Default activation duration:")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Picker("", selection: $store.keepAwakeDuration) {
                ForEach(KeepAwakeDuration.allCases) { duration in
                    Text(duration.menuTitle).tag(duration)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(store.isActionBusy(.keepAwake))

            Divider()

            Toggle("Keep awake when the lid is closed", isOn: Binding(
                get: { keepAwakeWhenLidClosed },
                set: { value in
                    keepAwakeWhenLidClosed = value
                    KeepAwakePreferences.keepAwakeWhenLidClosed = value
                    if store.snapshots[.keepAwake]?.isOn == true {
                        store.set(.keepAwake, enabled: true)
                    } else {
                        store.refreshAsync(.keepAwake)
                    }
                }
            ))
            .disabled(store.isActionBusy(.keepAwake))

            Text("Disables system sleep with administrator permission while Keep Awake is active. Keep your Mac plugged in when using this.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    refreshSleepStatus()
                    store.refreshAsync(.keepAwake)
                } label: {
                    Label(sleepStatusLoading ? "Checking..." : "Refresh Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(sleepStatusLoading || store.isActionBusy(.keepAwake))

                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openBattery(),
                        store: store,
                        failureMessage: "Could not open Battery settings."
                    )
                } label: {
                    Label("Battery", systemImage: "battery.50percent")
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            keepAwakeWhenLidClosed = KeepAwakePreferences.keepAwakeWhenLidClosed
            refreshSleepStatus()
        }
    }

    private func refreshSleepStatus() {
        guard !sleepStatusLoading else {
            pendingSleepStatusRefresh = true
            return
        }
        sleepStatusLoading = true
        DispatchQueue.global(qos: .utility).async {
            let disabled = KeepAwakePreferences.sleepDisabled
            DispatchQueue.main.async {
                sleepDisabled = disabled
                let shouldRefreshAgain = pendingSleepStatusRefresh
                pendingSleepStatusRefresh = false
                sleepStatusLoading = false
                if shouldRefreshAgain {
                    refreshSleepStatus()
                }
            }
        }
    }

    private var sleepStatusMessage: String {
        if sleepStatusLoading {
            return "Checking system sleep status..."
        }
        return sleepDisabled
            ? "System sleep is disabled while Keep Awake is active."
            : "Lid-closed mode may request administrator permission when activated."
    }
}

private struct DarkModePreferencesPanel: View {
    @ObservedObject var store: SwitchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Schedule:", selection: $store.darkModeScheduleMode) {
                ForEach(DarkModeScheduleMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .disabled(store.isActionBusy(.darkMode))

            if store.darkModeScheduleMode == .custom {
                TimeOfDayPickerRow(label: "From", time: $store.darkModeScheduleStart)
                    .disabled(store.isActionBusy(.darkMode))
                TimeOfDayPickerRow(label: "To", time: $store.darkModeScheduleEnd)
                    .disabled(store.isActionBusy(.darkMode))

                Text("Dark Mode will turn on from \(store.darkModeScheduleStart.display) to \(store.darkModeScheduleEnd.display).")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if store.darkModeScheduleMode == .sunriseSunset {
                Text(store.darkModeSunScheduleDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(darkModeLocationNeedsAttention ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Dark Mode turns on at sunset and turns off at sunrise.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        store.requestDarkModeLocation()
                    } label: {
                        Label("Refresh Location", systemImage: "location")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isActionBusy(.darkMode))

                    if darkModeLocationNeedsAttention {
                        Button {
                            reportOpenResult(
                                SystemSettingsLinks.openLocationServices(),
                                store: store,
                                failureMessage: "Could not open Location Services settings."
                            )
                        } label: {
                            Label("Open Location Settings", systemImage: "gearshape")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isActionBusy(.darkMode))
                    }
                }
            } else {
                Text("Use the dashboard switch or global shortcut to change Dark Mode manually.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var darkModeLocationNeedsAttention: Bool {
        let status = store.darkModeSunScheduleDescription.lowercased()
        return status.contains("not available")
            || status.contains("denied")
            || status.contains("restricted")
            || status.contains("off")
            || status.contains("failed")
    }
}

private struct NightShiftPreferencesPanel: View {
    @ObservedObject var store: SwitchStore
    @State private var autoScheduleEnabled = false
    @State private var nightShiftSupported: Bool?
    @State private var isRefreshingNightShift = false
    @State private var pendingNightShiftRefresh = false
    @State private var isUpdatingNightShiftSchedule = false
    @State private var statusText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isRefreshingNightShift && nightShiftSupported == nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking Night Shift support...")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else if nightShiftSupported == false {
                RecoveryNotice(
                    symbol: "lightbulb.fill",
                    title: "Night Shift is not available",
                    message: "The current Mac or display did not report Night Shift support."
                ) {
                    reportOpenResult(
                        SystemSettingsLinks.openDisplays(),
                        store: store,
                        failureMessage: "Could not open Displays settings."
                    )
                }
            } else {
                Toggle("Auto change from sunrise to sunset", isOn: Binding(
                    get: { autoScheduleEnabled },
                    set: { value in
                        updateNightShiftAutoSchedule(value)
                    }
                ))
                .disabled(isRefreshingNightShift || isUpdatingNightShiftSchedule || store.isActionBusy(.nightShift))

                Text("This changes the same macOS Night Shift schedule mode used by System Settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let statusText {
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(statusText.hasPrefix("Could not") || statusText.contains("not available") ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    refreshNightShift()
                } label: {
                    Label(isRefreshingNightShift ? "Checking..." : "Refresh Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshingNightShift || isUpdatingNightShiftSchedule || store.isActionBusy(.nightShift))

                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openDisplays(),
                        store: store,
                        failureMessage: "Could not open Displays settings."
                    )
                } label: {
                    Label("Display Settings", systemImage: "display")
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            refreshNightShift()
        }
    }

    private func refreshNightShift() {
        guard !isRefreshingNightShift else {
            pendingNightShiftRefresh = true
            return
        }
        isRefreshingNightShift = true
        DispatchQueue.global(qos: .utility).async {
            let latest = NightShiftPreferences.autoScheduleEnabled
            DispatchQueue.main.async {
                autoScheduleEnabled = latest ?? false
                nightShiftSupported = latest != nil
                let shouldRefreshAgain = pendingNightShiftRefresh
                pendingNightShiftRefresh = false
                isRefreshingNightShift = false
                store.refreshAsync(.nightShift)
                if shouldRefreshAgain {
                    refreshNightShift()
                }
            }
        }
    }

    private func updateNightShiftAutoSchedule(_ value: Bool) {
        guard !isUpdatingNightShiftSchedule, !store.isActionBusy(.nightShift) else { return }
        isUpdatingNightShiftSchedule = true
        autoScheduleEnabled = value
        statusText = "Updating Night Shift schedule..."

        DispatchQueue.global(qos: .userInitiated).async {
            let error = NightShiftPreferences.setAutoScheduleEnabled(value)
            let latest = NightShiftPreferences.autoScheduleEnabled
            DispatchQueue.main.async {
                isUpdatingNightShiftSchedule = false
                autoScheduleEnabled = latest ?? value
                nightShiftSupported = latest != nil
                if let error {
                    statusText = error
                } else {
                    statusText = value
                        ? "Night Shift will follow sunrise and sunset."
                        : "Night Shift schedule is manual."
                }
                store.refreshAsync(.nightShift)
                if pendingNightShiftRefresh {
                    pendingNightShiftRefresh = false
                    refreshNightShift()
                }
            }
        }
    }
}

private struct TimeOfDayPickerRow: View {
    let label: String
    @Binding var time: TimeOfDay

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 46, alignment: .trailing)
            Stepper(value: Binding(
                get: { time.hour },
                set: { time = TimeOfDay(hour: min(max($0, 0), 23), minute: time.minute) }
            ), in: 0...23) {
                Text(String(format: "%02d", time.hour))
                    .monospacedDigit()
                    .frame(width: 30)
            }
            Stepper(value: Binding(
                get: { time.minute },
                set: { time = TimeOfDay(hour: time.hour, minute: min(max($0, 0), 59)) }
            ), in: 0...59, step: 5) {
                Text(String(format: "%02d", time.minute))
                    .monospacedDigit()
                    .frame(width: 30)
            }
        }
        .font(.system(size: 14))
    }
}

private struct PlayMusicPreferencesPanel: View {
    @ObservedObject var store: SwitchStore
    @State private var selectedPlayer = PlayMusicPreferences.selectedPlayer
    @State private var playerInfos: [PlayMusicPlayerInfo] = []
    @State private var isRefreshingPlayers = false
    @State private var pendingPlayersRefresh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Player:", selection: $selectedPlayer) {
                ForEach(PlayMusicPlayerSelection.allCases) { player in
                    Text(player.title).tag(player)
                }
            }
            .pickerStyle(.menu)
            .disabled(isRefreshingPlayers || store.isActionBusy(.playMusic))
            .onChange(of: selectedPlayer) { _, value in
                PlayMusicPreferences.selectedPlayer = value
                store.refreshAsync(.playMusic)
            }

            Text("Automatic controls the running player, preferring the one that is currently playing. Choose a specific player to make the dashboard switch always target it.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                if isRefreshingPlayers && playerInfos.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking installed players...")
                            .font(.system(size: 13.2, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(playerInfos) { info in
                        HStack(spacing: 8) {
                            Image(systemName: info.isRunning ? "play.circle.fill" : (info.isInstalled ? "checkmark.circle.fill" : "minus.circle"))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(info.isRunning ? Color.green : (info.isInstalled ? Color.secondary : Color.orange))
                                .frame(width: 18)
                            Text(info.displayName)
                                .font(.system(size: 13.2, weight: .medium))
                            Spacer()
                            Text(info.isRunning ? "Running" : (info.isInstalled ? "Installed" : "Not installed"))
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(info.isInstalled ? Color.secondary : Color.orange)
                        }
                    }
                }
            }
            .padding(10)
            .background(PreferencesColors.subduedFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            HStack(spacing: 10) {
                if let target = openTarget {
                    Button {
                        if reportOpenResult(
                            PlayMusicPreferences.open(target),
                            store: store,
                            failureMessage: "Could not open \(target.displayName)."
                        ) {
                            refreshPlayersSoon()
                        }
                    } label: {
                        Label("Open \(target.displayName)", systemImage: "play.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshingPlayers || store.isActionBusy(.playMusic))
                }

                Button {
                    refreshPlayers()
                } label: {
                    Label(isRefreshingPlayers ? "Checking..." : "Refresh Players", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshingPlayers || store.isActionBusy(.playMusic))

                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openAutomation(),
                        store: store,
                        failureMessage: "Could not open Automation settings."
                    )
                } label: {
                    Label("Review Automation", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }

            if let snapshot = store.snapshots[.playMusic] {
                Text(snapshot.warning ?? snapshot.subtitle ?? "No active player")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(snapshot.warning == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            selectedPlayer = PlayMusicPreferences.selectedPlayer
            refreshPlayers()
        }
        .onReceive(Timer.publish(every: 6, on: .main, in: .common).autoconnect()) { _ in
            refreshPlayers()
        }
    }

    private var openTarget: PlayMusicPlayerInfo? {
        if selectedPlayer == .automatic {
            if let music = playerInfos.first(where: { $0.selection == .music && $0.isInstalled }) {
                return music
            }
            return playerInfos.first { $0.isInstalled }
        }
        return playerInfos.first { $0.selection == selectedPlayer && $0.isInstalled }
    }

    private func refreshPlayers() {
        guard !isRefreshingPlayers else {
            pendingPlayersRefresh = true
            return
        }
        isRefreshingPlayers = true
        DispatchQueue.global(qos: .utility).async {
            let refreshedPlayers = PlayMusicPreferences.playerInfos
            DispatchQueue.main.async {
                playerInfos = refreshedPlayers
                let shouldRefreshAgain = pendingPlayersRefresh
                pendingPlayersRefresh = false
                isRefreshingPlayers = false
                store.refreshAsync(.playMusic)
                if shouldRefreshAgain {
                    refreshPlayers()
                }
            }
        }
    }

    private func refreshPlayersSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            refreshPlayers()
            store.refreshAsync(.playMusic)
        }
    }
}

private struct EjectDiskPreferencesPanel: View {
    @ObservedObject var store: SwitchStore
    @State private var excludedPaths: [String] = []
    @State private var mountedVolumes: [EjectableVolumeOption] = []
    @State private var isRefreshingVolumes = false
    @State private var pendingVolumesRefresh = false
    private static let exclusionSelectionError = "Choose a removable or ejectable volume to exclude."

    private var snapshot: SwitchSnapshot {
        store.snapshots[.ejectDisk] ?? .off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: snapshot.isAvailable ? "externaldrive.fill" : "externaldrive.badge.xmark")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(snapshot.isAvailable ? Color.accentColor : Color.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.subtitle ?? "No ejectable disks")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Only removable or ejectable volumes that are not excluded will be ejected.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            ConfirmationToggle(kind: .ejectDisk, title: "Ask before ejecting disks")

            Text("Mounted removable volumes:")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            if mountedVolumes.isEmpty && isRefreshingVolumes {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking removable volumes...")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else if mountedVolumes.isEmpty {
                Text("No removable or ejectable volumes are currently mounted.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(mountedVolumes) { volume in
                            HStack(spacing: 9) {
                                Image(systemName: volume.isExcluded ? "externaldrive.badge.xmark" : "externaldrive.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(volume.isExcluded ? Color.secondary : Color.accentColor)
                                    .frame(width: 22)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(volume.name)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .lineLimit(1)
                                    Text(volume.path)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer(minLength: 8)

                                SettingsPill(
                                    text: volume.isBuiltInExcluded ? "Protected" : (volume.isExcluded ? "Excluded" : "Included"),
                                    color: volume.isExcluded ? Color.secondary : Color.accentColor
                                )

                                Button {
                                    if volume.isExcluded {
                                        EjectDiskPreferences.include(volume.path)
                                        clearExclusionSelectionError()
                                    } else if EjectDiskPreferences.exclude(volume.url) {
                                        clearExclusionSelectionError()
                                    } else {
                                        store.lastError = Self.exclusionSelectionError
                                    }
                                    refresh()
                                } label: {
                                    Text(volume.isBuiltInExcluded ? "Protected" : (volume.isExcluded ? "Include" : "Exclude"))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(volume.isBuiltInExcluded || isRefreshingVolumes || store.isActionBusy(.ejectDisk))
                                .help(volume.isBuiltInExcluded
                                      ? "This volume is excluded by default to avoid ejecting a system or Boot Camp volume."
                                      : (volume.isExcluded ? "Remove this saved exclusion." : "Exclude this volume from Eject Disk."))
                            }
                            .padding(10)
                            .background(PreferencesColors.subduedFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 156)
            }

            Text("Saved exclusions:")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            if excludedPaths.isEmpty {
                Text("No excluded disks.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(excludedPaths, id: \.self) { path in
                            HStack(spacing: 8) {
                                Image(systemName: "externaldrive")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .lineLimit(1)
                                    Text(path)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Button {
                                    EjectDiskPreferences.remove(path)
                                    clearExclusionSelectionError()
                                    refresh()
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .disabled(isRefreshingVolumes || store.isActionBusy(.ejectDisk))
                            }
                            .font(.system(size: 13.5))
                        }
                    }
                }
                .frame(maxHeight: 118)
            }

            HStack(spacing: 10) {
                Button {
                    store.trigger(.ejectDisk)
                    scheduleAfterSwitchActionSettles(store: store, kind: .ejectDisk) {
                        refresh()
                    }
                } label: {
                    Label(ejectActionTitle, systemImage: "eject.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!snapshot.isAvailable || isRefreshingVolumes || store.isActionBusy(.ejectDisk))

                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = true
                    panel.prompt = "Exclude"
                    if panel.runModal() == .OK {
                        if !EjectDiskPreferences.add(panel.urls) {
                            store.lastError = Self.exclusionSelectionError
                        } else {
                            clearExclusionSelectionError()
                        }
                        refresh()
                    }
                } label: {
                    Label("Choose Exclusions", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshingVolumes || store.isActionBusy(.ejectDisk))

                Button {
                    refresh()
                } label: {
                    Label(isRefreshingVolumes ? "Checking..." : "Refresh Disks", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshingVolumes || store.isActionBusy(.ejectDisk))

                Button {
                    openWorkspaceURLOrReport(
                        AppLinks.diskUtility,
                        store: store,
                        failureMessage: "Could not open Disk Utility."
                    )
                } label: {
                    Label("Disk Utility", systemImage: "internaldrive")
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        guard !isRefreshingVolumes else {
            pendingVolumesRefresh = true
            return
        }
        isRefreshingVolumes = true
        DispatchQueue.global(qos: .utility).async {
            let excluded = EjectDiskPreferences.excludedPaths
            let volumes = EjectDiskPreferences.mountedVolumeOptions
            DispatchQueue.main.async {
                excludedPaths = excluded
                mountedVolumes = volumes
                let shouldRefreshAgain = pendingVolumesRefresh
                pendingVolumesRefresh = false
                isRefreshingVolumes = false
                store.refreshAsync(.ejectDisk)
                if shouldRefreshAgain {
                    refresh()
                }
            }
        }
    }

    private func clearExclusionSelectionError() {
        if store.lastError == Self.exclusionSelectionError {
            store.clearLastError()
        }
    }

    private var ejectActionTitle: String {
        if store.actionsPreparing.contains(.ejectDisk) {
            return "Checking..."
        }
        return store.actionsInProgress.contains(.ejectDisk) ? "Ejecting..." : "Eject Now"
    }
}

private struct XcodeCleanPreferencesPanel: View {
    @ObservedObject var store: SwitchStore

    private var snapshot: SwitchSnapshot {
        store.snapshots[.xcodeClean] ?? .off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: snapshot.isAvailable ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundStyle(snapshot.isAvailable ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.subtitle ?? "DerivedData status unknown")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Mac Switch removes the contents of Xcode DerivedData and then refreshes the size estimate.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ConfirmationToggle(kind: .xcodeClean, title: "Ask before cleaning DerivedData")

            HStack(spacing: 10) {
                Button {
                    store.trigger(.xcodeClean)
                } label: {
                    Label(store.isActionBusy(.xcodeClean) ? "Cleaning..." : "Clean Now", systemImage: "hammer.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!snapshot.isAvailable || store.isActionBusy(.xcodeClean))

                Button {
                    XcodeCleanPreferences.refreshSizeEstimate()
                    store.refreshAsync(.xcodeClean)
                } label: {
                    Label("Refresh Size", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.isRefreshing || store.isActionBusy(.xcodeClean))

                Button {
                    reportOpenResult(
                        XcodeCleanPreferences.revealDerivedData(),
                        store: store,
                        failureMessage: "Could not reveal Xcode DerivedData."
                    )
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            store.refreshAsync(.xcodeClean)
        }
    }
}

private struct MicrophonePreferencesPanel: View {
    @ObservedObject var store: SwitchStore

    private var snapshot: SwitchSnapshot {
        store.snapshots[.muteMicrophone] ?? .off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusSummaryRow(
                symbol: snapshot.isAvailable ? "mic.fill" : "mic.slash.fill",
                title: snapshot.isAvailable ? (snapshot.isOn ? "Microphone muted" : "Microphone active") : "Microphone control unavailable",
                message: snapshot.warning ?? snapshot.subtitle ?? "Mac Switch controls the default input device when macOS exposes mute or input volume."
            )

            HStack(spacing: 10) {
                Button {
                    store.toggle(.muteMicrophone)
                } label: {
                    Label(snapshot.isOn ? "Unmute" : "Mute", systemImage: snapshot.isOn ? "mic.fill" : "mic.slash.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!snapshot.isAvailable || store.isActionBusy(.muteMicrophone))

                Button {
                    store.refreshAsync(.muteMicrophone)
                } label: {
                    Label("Refresh Input", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.isActionBusy(.muteMicrophone))

                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openSound(),
                        store: store,
                        failureMessage: "Could not open Sound settings."
                    )
                } label: {
                    Label("Sound Settings", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            store.refreshAsync(.muteMicrophone)
        }
    }
}

private struct DesktopDockPreferencesPanel: View {
    let kind: SwitchKind
    @ObservedObject var store: SwitchStore

    private var snapshot: SwitchSnapshot {
        store.snapshots[kind] ?? .off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusSummaryRow(
                symbol: kind.modernSymbol,
                title: snapshot.isAvailable ? (snapshot.isOn ? "Currently enabled" : "Currently disabled") : "Needs attention",
                message: snapshot.warning ?? snapshot.subtitle ?? kind.preferenceDescription
            )

            HStack(spacing: 10) {
                Button {
                    store.toggle(kind)
                } label: {
                    Label(snapshot.isOn ? "Off" : "On", systemImage: "switch.2")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!snapshot.isAvailable || store.isActionBusy(kind))

                Button {
                    store.refreshAsync(kind)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.isActionBusy(kind))

                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openDesktopDock(),
                        store: store,
                        failureMessage: "Could not open Desktop & Dock settings."
                    )
                } label: {
                    Label("Settings", systemImage: "dock.rectangle")
                }
                .buttonStyle(.bordered)
            }

            Text("These switches update Finder, Dock, or WindowManager defaults and refresh the affected system process when macOS accepts the change.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            store.refreshAsync(kind)
        }
    }
}

private struct TrashPreferencesPanel: View {
    @ObservedObject var store: SwitchStore
    @State private var itemCount = 0
    @State private var isRefreshingCount = false
    @State private var pendingCountRefresh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusSummaryRow(
                symbol: "trash.fill",
                title: trashTitle,
                message: "Empty Trash uses Finder automation so macOS can perform the same operation as Finder."
            )

            ConfirmationToggle(kind: .emptyTrash, title: "Ask before emptying Trash")

            HStack(spacing: 10) {
                Button {
                    store.trigger(.emptyTrash)
                    scheduleAfterSwitchActionSettles(store: store, kind: .emptyTrash) {
                        refreshCount()
                    }
                } label: {
                    Label(emptyTrashActionTitle, systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(itemCount == 0 || isRefreshingCount || store.isActionBusy(.emptyTrash))

                Button {
                    refreshCount()
                } label: {
                    Label(isRefreshingCount ? "Checking..." : "Refresh Count", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshingCount || store.isActionBusy(.emptyTrash))

                Button {
                    reportOpenResult(
                        TrashPreferences.openTrash(),
                        store: store,
                        failureMessage: "Could not open Trash."
                    )
                } label: {
                    Label("Open Trash", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openAutomation(),
                        store: store,
                        failureMessage: "Could not open Automation settings."
                    )
                } label: {
                    Label("Automation", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            refreshCount()
        }
    }

    private var trashTitle: String {
        if isRefreshingCount && itemCount == 0 {
            return "Checking Trash..."
        }
        return itemCount == 0 ? "Trash empty" : "\(itemCount) item\(itemCount == 1 ? "" : "s") in Trash"
    }

    private var emptyTrashActionTitle: String {
        if store.actionsPreparing.contains(.emptyTrash) {
            return "Checking..."
        }
        return store.actionsInProgress.contains(.emptyTrash) ? "Emptying..." : "Empty Now"
    }

    private func refreshCount() {
        guard !isRefreshingCount else {
            pendingCountRefresh = true
            return
        }
        isRefreshingCount = true
        DispatchQueue.global(qos: .utility).async {
            let count = TrashPreferences.itemCount
            DispatchQueue.main.async {
                itemCount = count
                let shouldRefreshAgain = pendingCountRefresh
                pendingCountRefresh = false
                isRefreshingCount = false
                store.refreshAsync(.emptyTrash)
                if shouldRefreshAgain {
                    refreshCount()
                }
            }
        }
    }

}

private struct PasteboardPreferencesPanel: View {
    @ObservedObject var store: SwitchStore
    @State private var itemCount = 0
    @State private var isRefreshingCount = false
    @State private var pendingCountRefresh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusSummaryRow(
                symbol: "doc.on.clipboard",
                title: pasteboardTitle,
                message: "Clear the general pasteboard without touching files or app documents."
            )

            ConfirmationToggle(kind: .emptyPasteboard, title: "Ask before clearing pasteboard")

            HStack(spacing: 10) {
                Button {
                    store.trigger(.emptyPasteboard)
                    scheduleAfterSwitchActionSettles(store: store, kind: .emptyPasteboard) {
                        refreshCount()
                    }
                } label: {
                    Label(pasteboardActionTitle, systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(itemCount == 0 || isRefreshingCount || store.isActionBusy(.emptyPasteboard))

                Button {
                    refreshCount()
                } label: {
                    Label(isRefreshingCount ? "Checking..." : "Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshingCount || store.isActionBusy(.emptyPasteboard))
            }
        }
        .onAppear {
            refreshCount()
        }
    }

    private var pasteboardTitle: String {
        if isRefreshingCount && itemCount == 0 {
            return "Checking Pasteboard..."
        }
        return itemCount == 0 ? "Pasteboard empty" : "\(itemCount) item\(itemCount == 1 ? "" : "s") on pasteboard"
    }

    private var pasteboardActionTitle: String {
        if store.actionsPreparing.contains(.emptyPasteboard) {
            return "Checking..."
        }
        return store.actionsInProgress.contains(.emptyPasteboard) ? "Clearing..." : "Clear Now"
    }

    private func refreshCount() {
        guard !isRefreshingCount else {
            pendingCountRefresh = true
            return
        }
        isRefreshingCount = true
        DispatchQueue.main.async {
            let count = PasteboardPreferences.itemCount
            itemCount = count
            let shouldRefreshAgain = pendingCountRefresh
            pendingCountRefresh = false
            isRefreshingCount = false
            store.refreshAsync(.emptyPasteboard)
            if shouldRefreshAgain {
                refreshCount()
            }
        }
    }

}

private struct HideWindowsPreferencesPanel: View {
    @ObservedObject var store: SwitchStore
    @State private var hiddenCount = 0
    @State private var hidableCount = 0
    @State private var isRefreshingCounts = false
    @State private var isShowingHidden = false
    @State private var pendingCountsRefresh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusSummaryRow(
                symbol: "macwindow.on.rectangle",
                title: hiddenWindowsTitle,
                message: hiddenCount == 0
                    ? "Hide Windows hides regular running apps except Mac Switch."
                    : "\(hiddenCount) app\(hiddenCount == 1 ? "" : "s") already hidden."
            )

            HStack(spacing: 10) {
                Button {
                    store.trigger(.hideWindows)
                    scheduleAfterSwitchActionSettles(store: store, kind: .hideWindows) {
                        refreshCounts()
                    }
                } label: {
                    Label(hideWindowsActionTitle, systemImage: "eye.slash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(hidableCount == 0 || isRefreshingCounts || isShowingHidden || store.isActionBusy(.hideWindows))

                Button {
                    showHiddenApps()
                } label: {
                    Label(isShowingHidden ? "Showing..." : "Show Hidden", systemImage: "eye")
                }
                .buttonStyle(.bordered)
                .disabled(hiddenCount == 0 || isRefreshingCounts || isShowingHidden || store.isActionBusy(.hideWindows))

                Button {
                    refreshCounts()
                    store.refreshAsync(.hideWindows)
                } label: {
                    Label(isRefreshingCounts ? "Checking..." : "Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshingCounts || isShowingHidden || store.isActionBusy(.hideWindows))
            }
        }
        .onAppear {
            refreshCounts()
            store.refreshAsync(.hideWindows)
        }
    }

    private var hiddenWindowsTitle: String {
        if isRefreshingCounts && hidableCount == 0 {
            return "Checking visible apps..."
        }
        return "\(hidableCount) visible app\(hidableCount == 1 ? "" : "s") can be hidden"
    }

    private var hideWindowsActionTitle: String {
        if store.actionsPreparing.contains(.hideWindows) {
            return "Checking..."
        }
        return store.actionsInProgress.contains(.hideWindows) ? "Hiding..." : "Hide Now"
    }

    private func showHiddenApps() {
        guard !isShowingHidden else { return }
        isShowingHidden = true
        DispatchQueue.main.async {
            let result = HideWindowsPreferences.unhideAll()
            isShowingHidden = false
            if !result.failed.isEmpty {
                store.lastError = "Could not show \(HideWindowsPreferences.joinedAppNames(result.failed))."
            } else if store.lastError?.hasPrefix("Could not show ") == true {
                store.clearLastError()
            }
            refreshCountsSoon()
            store.refreshAsync(.hideWindows)
        }
    }

    private func refreshCounts() {
        guard !isRefreshingCounts else {
            pendingCountsRefresh = true
            return
        }
        isRefreshingCounts = true
        DispatchQueue.main.async {
            let hidable = HideWindowsPreferences.hidableApps.count
            let hidden = HideWindowsPreferences.hiddenApps.count
            hidableCount = hidable
            hiddenCount = hidden
            let shouldRefreshAgain = pendingCountsRefresh
            pendingCountsRefresh = false
            isRefreshingCounts = false
            store.refreshAsync(.hideWindows)
            if shouldRefreshAgain {
                refreshCounts()
            }
        }
    }

    private func refreshCountsSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refreshCounts()
        }
    }
}

private struct LockScreenPreferencesPanel: View {
    let kind: SwitchKind
    @ObservedObject var store: SwitchStore

    private var snapshot: SwitchSnapshot {
        store.snapshots[kind] ?? .off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusSummaryRow(
                symbol: kind == .screenSaver ? "display" : "lock.display",
                title: kind == .screenSaver ? "Screen saver action" : "Lock screen action",
                message: snapshot.warning ?? snapshot.subtitle ?? kind.preferenceDescription
            )

            HStack(spacing: 10) {
                Button {
                    store.trigger(kind)
                } label: {
                    Label(lockActionTitle, systemImage: kind.actionSymbol)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!snapshot.isAvailable || store.isActionBusy(kind))

                Button {
                    store.refreshAsync(kind)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.isActionBusy(kind))

                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openLockScreen(),
                        store: store,
                        failureMessage: "Could not open Lock Screen settings."
                    )
                } label: {
                    Label("Lock Screen Settings", systemImage: "lock.display")
                }
                .buttonStyle(.bordered)

                if kind == .lockScreen {
                    Button {
                        reportOpenResult(
                            SystemSettingsLinks.openAutomation(),
                            store: store,
                            failureMessage: "Could not open Automation settings."
                        )
                    } label: {
                        Label("Automation", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .onAppear {
            store.refreshAsync(kind)
        }
    }

    private var lockActionTitle: String {
        if store.isActionBusy(kind) {
            return kind == .screenSaver ? "Starting..." : "Locking..."
        }
        return kind == .screenSaver ? "Start Screen Saver" : "Lock Now"
    }
}

private struct DisplayUtilityPreferencesPanel: View {
    let kind: SwitchKind
    @ObservedObject var store: SwitchStore

    private var snapshot: SwitchSnapshot {
        store.snapshots[kind] ?? .off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusSummaryRow(
                symbol: kind == .displaySleep ? "display.trianglebadge.exclamationmark" : "sun.max.fill",
                title: displayTitle,
                message: snapshot.warning ?? snapshot.subtitle ?? kind.preferenceDescription
            )

            HStack(spacing: 10) {
                Button {
                    if kind.isMomentaryAction {
                        store.trigger(kind)
                    } else {
                        store.toggle(kind)
                    }
                } label: {
                    Label(actionTitle, systemImage: kind.isMomentaryAction ? kind.actionSymbol : "switch.2")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!snapshot.isAvailable || store.isActionBusy(kind))

                Button {
                    store.refreshAsync(kind)
                } label: {
                    Label("Refresh Display", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.isActionBusy(kind))

                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openDisplays(),
                        store: store,
                        failureMessage: "Could not open Displays settings."
                    )
                } label: {
                    Label("Display Settings", systemImage: "display")
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            store.refreshAsync(kind)
        }
    }

    private var displayTitle: String {
        if kind == .displaySleep { return "Display sleep action" }
        if snapshot.isAvailable { return snapshot.isOn ? "True Tone enabled" : "True Tone disabled" }
        return "True Tone unavailable"
    }

    private var actionTitle: String {
        if kind == .displaySleep {
            return store.isActionBusy(kind) ? "Sleeping..." : "Sleep Display"
        }
        return snapshot.isOn ? "Turn Off" : "Turn On"
    }
}

private struct LowPowerModePreferencesPanel: View {
    @ObservedObject var store: SwitchStore

    private var snapshot: SwitchSnapshot {
        store.snapshots[.lowPowerMode] ?? .off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusSummaryRow(
                symbol: "battery.25percent",
                title: snapshot.isAvailable ? (snapshot.isOn ? "Low Power Mode enabled" : "Low Power Mode available") : "Low Power Mode unavailable",
                message: snapshot.warning ?? "Low Power Mode uses macOS power mode support reported by pmset."
            )

            HStack(spacing: 10) {
                Button {
                    store.toggle(.lowPowerMode)
                } label: {
                    Label(snapshot.isOn ? "Turn Off" : "Turn On", systemImage: "battery.25percent")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!snapshot.isAvailable || store.isActionBusy(.lowPowerMode))

                Button {
                    store.refreshAsync(.lowPowerMode)
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.isActionBusy(.lowPowerMode))

                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openBattery(),
                        store: store,
                        failureMessage: "Could not open Battery settings."
                    )
                } label: {
                    Label("Battery", systemImage: "battery.50percent")
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            store.refreshAsync(.lowPowerMode)
        }
    }
}

private struct EnergyModePreferencesPanel: View {
    @ObservedObject var store: SwitchStore
    @State private var selectedMode = EnergyModePreferences.storedSelection
    @State private var supportedModes: [EnergyModeSelection] = []
    @State private var isLoadingModes = false
    @State private var pendingModesRefresh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoadingModes {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking supported power modes...")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if supportedModes.isEmpty {
                RecoveryNotice(
                    symbol: "battery.50percent",
                    title: "Power modes are not available",
                    message: "macOS did not report Low Power or High Power mode support for this Mac."
                ) {
                    reportOpenResult(
                        SystemSettingsLinks.openBattery(),
                        store: store,
                        failureMessage: "Could not open Battery settings."
                    )
                }
            } else {
                Picker("Mode:", selection: $selectedMode) {
                    ForEach(supportedModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedMode) { _, value in
                    EnergyModePreferences.selectedMode = value
                    store.refreshAsync(.energyMode)
                }
                .disabled(store.isActionBusy(.energyMode))
            }

            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    loadSupportedModes(force: true)
                    store.refreshAsync(.energyMode)
                } label: {
                    Label("Refresh Modes", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingModes || store.isActionBusy(.energyMode))

                Button {
                    reportOpenResult(
                        SystemSettingsLinks.openBattery(),
                        store: store,
                        failureMessage: "Could not open Battery settings."
                    )
                } label: {
                    Label("Battery", systemImage: "battery.50percent")
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            loadSupportedModes()
            store.refreshAsync(.energyMode)
        }
    }

    private var description: String {
        if isLoadingModes {
            return "macOS is reporting the power modes available on this Mac."
        }
        if supportedModes.isEmpty {
            return "macOS did not report Low Power or High Power mode support for this Mac."
        }
        if supportedModes.count == 1, let mode = supportedModes.first {
            return "\(mode.title) is the only power mode macOS reports for this Mac."
        }
        return "Choose which macOS power mode the Energy Mode switch toggles."
    }

    private func loadSupportedModes(force: Bool = false) {
        guard !isLoadingModes else {
            pendingModesRefresh = pendingModesRefresh || force
            return
        }
        isLoadingModes = true
        DispatchQueue.global(qos: .utility).async {
            let supported = EnergyModeSelection.supportedCases
            DispatchQueue.main.async {
                supportedModes = supported
                isLoadingModes = false
                let shouldRefreshAgain = pendingModesRefresh
                pendingModesRefresh = false
                reconcileSelection()
                if shouldRefreshAgain {
                    loadSupportedModes(force: true)
                }
            }
        }
    }

    private func reconcileSelection() {
        let supported = supportedModes
        let preferred = EnergyModePreferences.selectedMode(among: supported)
        selectedMode = preferred
        guard !supported.isEmpty else {
            return
        }
        if EnergyModePreferences.storedSelection != preferred {
            EnergyModePreferences.selectedMode = preferred
        }
    }
}

private struct AccessibilityPreferencesPanel: View {
    let kind: SwitchKind
    @ObservedObject var store: SwitchStore
    @State private var isTrusted = false
    @State private var isCheckingTrust = false
    @State private var pendingTrustCheck = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: trustIcon)
                    .foregroundStyle(trustColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trustTitle)
                        .font(.system(size: 14, weight: .medium))
                    Text(trustMessage)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                if reportOpenResult(
                    AccessibilityPermission.requestAndOpenSettings(),
                    store: store,
                    failureMessage: "Could not open Accessibility settings."
                ) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        refreshTrust(forceSwitchRefresh: true)
                    }
                }
            } label: {
                Label("Open System Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)

            Text(kind == .screenClean ? "Screen Cleaning locks keyboard and pointer input during cleaning mode." : "Lock Keyboard blocks keyboard input until you turn it off.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            refreshTrust()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refreshTrust()
        }
    }

    private func refreshTrust() {
        refreshTrust(forceSwitchRefresh: false)
    }

    private func refreshTrust(forceSwitchRefresh: Bool) {
        guard !isCheckingTrust else {
            pendingTrustCheck = pendingTrustCheck || forceSwitchRefresh
            return
        }
        isCheckingTrust = true
        DispatchQueue.global(qos: .utility).async {
            let latest = AccessibilityPermission.isTrusted
            DispatchQueue.main.async {
                let shouldRefreshSwitch = forceSwitchRefresh || latest != isTrusted
                isTrusted = latest
                let shouldCheckAgain = pendingTrustCheck
                pendingTrustCheck = false
                isCheckingTrust = false
                if shouldRefreshSwitch {
                    store.refreshAsync(kind)
                }
                if shouldCheckAgain {
                    refreshTrust(forceSwitchRefresh: true)
                }
            }
        }
    }

    private var trustIcon: String {
        if isCheckingTrust && !isTrusted {
            return "clock.badge.questionmark"
        }
        return isTrusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var trustColor: Color {
        if isCheckingTrust && !isTrusted {
            return .secondary
        }
        return isTrusted ? .green : .orange
    }

    private var trustTitle: String {
        if isCheckingTrust && !isTrusted {
            return "Checking accessibility permission"
        }
        return isTrusted ? "Accessibility permission granted" : "Accessibility permission required"
    }

    private var trustMessage: String {
        isTrusted
            ? "\(kind.title) can block input events."
            : "Grant access in Privacy & Security to let \(kind.title) block input events."
    }
}

private extension SwitchKind {
    var preferenceDescription: String {
        switch self {
        case .stageManager:
            return "Toggles macOS Stage Manager and refreshes Dock so the change is applied immediately."
        case .hideWidgets:
            return "Hides desktop widgets in normal desktop mode and Stage Manager when supported by macOS."
        case .muteMicrophone:
            return "Mutes the default input device when macOS exposes mute or input-volume control."
        case .hideDesktopIcons:
            return "Hides or restores desktop icons by updating Finder and restarting it."
        case .darkMode:
            return "Use the Dark Mode options panel to choose manual, custom, or sunrise/sunset scheduling."
        case .keepAwake:
            return "Use the Keep Awake options panel to choose duration and lid-closed behavior."
        case .screenSaver:
            return "Starts the system screen saver immediately from the dashboard action button."
        case .bluetoothAudio:
            return "Use the Bluetooth Audio options panel to choose a paired Bluetooth audio device."
        case .doNotDisturb:
            return "Use the Do Not Disturb options panel to configure the required Focus shortcuts."
        case .nightShift:
            return "Use the Night Shift options panel to control its sunrise/sunset schedule mode."
        case .trueTone:
            return "Toggles True Tone when the current Mac and display report support for it."
        case .playMusic:
            return "Use the Play Music options panel to choose Automatic, Music, iTunes, or Spotify."
        case .showHiddenFiles:
            return "Shows or hides hidden files in Finder and restarts Finder to apply the change."
        case .displaySleep:
            return "Puts connected displays to sleep immediately from the dashboard action button."
        case .screenResolution:
            return "Use the Screen Resolution options panel to choose display and target mode."
        case .screenClean:
            return "Use the Accessibility options panel to grant permission before cleaning mode blocks input."
        case .lockKeyboard:
            return "Use the Accessibility options panel to grant permission before keyboard locking."
        case .lockScreen:
            return "Locks the Mac immediately from the dashboard action button."
        case .xcodeClean:
            return "Removes Xcode DerivedData contents and reports progress from the dashboard."
        case .emptyTrash:
            return "Empties Trash from the dashboard action button; if Trash is empty, it returns without asking Finder."
        case .ejectDisk:
            return "Use the Eject Disk options panel to exclude volumes that should never be ejected."
        case .emptyPasteboard:
            return "Clears the general pasteboard immediately from the dashboard action button."
        case .hideWindows:
            return "Hides regular running apps except Mac Switch from the dashboard action button."
        case .hideDock:
            return "Toggles Dock auto-hide and restarts Dock to apply the change."
        case .lowPowerMode:
            return "Toggles macOS Low Power Mode when this Mac reports support for it."
        case .energyMode:
            return "Use the Energy Mode options panel to choose the power mode this switch toggles."
        }
    }
}

private struct DashboardDropDelegate: DropDelegate {
    let item: SwitchKind
    let store: SwitchStore
    let rowHeight: CGFloat
    let topInset: CGFloat
    @Binding var dragging: SwitchKind?
    @Binding var placement: DashboardDropPlacement?

    func dropEntered(info: DropInfo) {
        updatePlacement(using: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updatePlacement(using: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        updatePlacement(using: info)
        guard let source = dragging else {
            clearDragState()
            return false
        }
        guard let target = placement, target.item != source else {
            clearDragState()
            return true
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            switch target.position {
            case .before:
                store.move(source, before: target.item)
            case .after:
                store.move(source, after: target.item)
            }
            dragging = nil
            placement = nil
        }
        return true
    }

    func dropExited(info: DropInfo) {
        guard placement?.item == item else { return }
        withAnimation(.easeOut(duration: 0.10)) {
            placement = nil
        }
    }

    private func updatePlacement(using info: DropInfo) {
        guard let dragging, dragging != item else {
            if placement?.item == item {
                withAnimation(.easeOut(duration: 0.10)) {
                    placement = nil
                }
            }
            return
        }

        let next = DashboardDropPlacement(item: item, position: position(for: info))
        guard placement != next else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            placement = next
        }
    }

    private func position(for info: DropInfo) -> DashboardDropPlacement.Position {
        let rowY = info.location.y - topInset
        return rowY > rowHeight / 2 ? .after : .before
    }

    private func clearDragState() {
        withAnimation(.easeOut(duration: 0.10)) {
            dragging = nil
            placement = nil
        }
    }
}

struct ScreenCleanOverlayView: View {
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 22) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 58, weight: .regular))
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("Screen Cleaning Mode")
                        .font(.system(size: 38, weight: .semibold))
                    Text("Your keyboard is also locked")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                    Text("Failsafe exits automatically after 10 minutes")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.44))
                }

                VStack(spacing: 8) {
                    Text("Click Anywhere or Press Esc")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.12), in: Capsule())
                }
            }
            .foregroundStyle(.white.opacity(0.9))
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
