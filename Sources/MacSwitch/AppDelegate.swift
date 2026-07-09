import AppKit
import Combine
import CoreGraphics
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private enum PreferencesLayoutMode: String {
        case compact
        case detail
    }

    private let preferencesCompactContentSize = NSSize(width: 580, height: 440)
    private let preferencesExpandedContentSize = NSSize(width: 980, height: 460)
    private let preferencesMinimumContentHeight: CGFloat = 390
    private let store = SwitchStore()
    private let softwareUpdates = SoftwareUpdateManager.shared
    private var statusItem: NSStatusItem?
    private var dashboardWindow: DashboardPanel?
    private var preferencesWindow: NSWindow?
    private var preferencesLayoutMode: PreferencesLayoutMode = .compact
    private var preferencesResizeState: PreferencesResizeState?
    private var preferencesResizeTimer: Timer?
    private var preferencesWindowWasMovableByBackground = true
    private var cancellables: Set<AnyCancellable> = []
    private var dashboardLocalEventMonitor: Any?
    private var dashboardGlobalEventMonitor: Any?

    private struct PreferencesResizeState {
        let initialFrame: NSRect
        var deltaY: CGFloat
        var appliedFrame: NSRect?
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Self.requiresRegularActivation ? .regular : .accessory)
        if !store.activeModeSessions.isEmpty, softwareUpdates.updateChannel != .beta {
            softwareUpdates.updateChannel = .beta
        }
        softwareUpdates.requiresBetaChannel = { [weak store = self.store] in
            guard let store else { return false }
            return store.activeModeOperationID != nil || !store.activeModeSessions.isEmpty
        }
        softwareUpdates.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: [.leftMouseDown])
        item.button?.toolTip = "Mac Switch"
        item.button?.setAccessibilityLabel("Mac Switch")
        updateStatusIcon(store.menuBarIcon)

        store.$menuBarIcon
            .sink { [weak self] icon in self?.updateStatusIcon(icon) }
            .store(in: &cancellables)
        store.$enabledKinds
            .dropFirst()
            .sink { [weak self] _ in self?.resizeVisibleDashboardKeepingTopEdge() }
            .store(in: &cancellables)
        store.$enabledModeIDs
            .dropFirst()
            .sink { [weak self] _ in self?.resizeVisibleDashboardKeepingTopEdge() }
            .store(in: &cancellables)
        store.$activeModeSessions
            .dropFirst()
            .sink { [weak self] _ in self?.resizeVisibleDashboardKeepingTopEdge() }
            .store(in: &cancellables)
        store.$lastError
            .dropFirst()
            .sink { [weak self] _ in self?.resizeVisibleDashboardKeepingTopEdge() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(self, selector: #selector(openPreferences), name: .openMacSwitchPreferences, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resizePreferencesForLayout(_:)), name: .setMacSwitchPreferencesLayout, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(quit), name: .quitMacSwitch, object: nil)

        if Self.openCustomizeOnLaunch {
            store.preferredPreferencesTab = "customize"
        }

        if Self.openPreferencesOnLaunch || Self.openCustomizeOnLaunch || Self.preferencesSmokeMode {
            openPreferences()
        }

        DispatchQueue.main.async { [weak self] in
            self?.prewarmDashboard()
        }

        if Self.dashboardSmokeMode || Self.openDashboardOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.showDashboardForSmokeTest()
            }
        }

        if Self.preferencesSmokeMode || Self.dashboardSmokeMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.finishUISmokeTest()
            }
        }
    }

    private static var uiRegressionMode: Bool {
        CommandLine.arguments.contains("--ui-regression-mode")
    }

    private static var preferencesSmokeMode: Bool {
        CommandLine.arguments.contains("--ui-smoke-test")
    }

    private static var dashboardSmokeMode: Bool {
        CommandLine.arguments.contains("--dashboard-smoke-test")
    }

    private static var requiresRegularActivation: Bool {
        uiRegressionMode || preferencesSmokeMode || dashboardSmokeMode || openPreferencesOnLaunch
            || openCustomizeOnLaunch || openDashboardOnLaunch
    }

    private static var openPreferencesOnLaunch: Bool {
        CommandLine.arguments.contains("--open-preferences")
    }

    private static var openCustomizeOnLaunch: Bool {
        CommandLine.arguments.contains("--open-customize")
    }

    private static var openDashboardOnLaunch: Bool {
        CommandLine.arguments.contains("--open-dashboard")
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if dashboardWindow?.isVisible == true {
            hideDashboard()
        } else {
            showDashboard(relativeTo: button)
        }
    }

    @objc private func openPreferences() {
        hideDashboard()
        if Self.uiRegressionMode {
            NSApp.setActivationPolicy(.regular)
        }

        if preferencesWindow == nil {
            preferencesLayoutMode = initialPreferencesLayoutMode()
            let initialContentSize = preferencesContentSize(for: preferencesLayoutMode)
            let controller = NSHostingController(rootView: PreferencesView(store: store))
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: initialContentSize),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = makePreferencesContentController(
                hostingController: controller,
                initialContentSize: initialContentSize
            )
            window.title = "Preferences"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.delegate = self
            applyPreferencesResizeConstraints(to: window, layoutMode: preferencesLayoutMode)
            window.setContentSize(initialContentSize)
            centerPreferencesWindow(window)
            preferencesWindow = window
        } else if let window = preferencesWindow {
            keepPreferencesWindowVisible(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.orderFrontRegardless()
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func resizePreferencesForLayout(_ notification: Notification) {
        guard let rawMode = notification.userInfo?["mode"] as? String,
              let mode = PreferencesLayoutMode(rawValue: rawMode)
        else { return }
        resizePreferencesWindow(layoutMode: mode, animate: true)
    }

    private func resizePreferencesWindow(layoutMode: PreferencesLayoutMode, animate: Bool) {
        guard let window = preferencesWindow else { return }
        preferencesLayoutMode = layoutMode
        applyPreferencesResizeConstraints(to: window, layoutMode: layoutMode)
        let baseContentSize = preferencesContentSize(for: layoutMode)
        let currentContentHeight = window.contentView?.bounds.height ?? baseContentSize.height
        let targetContentHeight = min(
            max(baseContentSize.height, currentContentHeight),
            window.contentMaxSize.height
        )
        let targetContentSize = NSSize(width: baseContentSize.width, height: targetContentHeight)
        let targetFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize)).size
        var frame = window.frame
        let fixedLeftEdge = frame.minX
        let fixedTopEdge = frame.maxY
        frame.size = targetFrameSize
        frame.origin.x = fixedLeftEdge
        frame.origin.y = fixedTopEdge - targetFrameSize.height

        if let screen = Self.preferredScreenForPreferences() {
            let visibleFrame = screen.visibleFrame.insetBy(dx: 18, dy: 18)
            if frame.maxX > visibleFrame.maxX {
                frame.origin.x = max(visibleFrame.minX, visibleFrame.maxX - frame.width)
            }
            if frame.minX < visibleFrame.minX {
                frame.origin.x = visibleFrame.minX
            }
            if frame.maxY > visibleFrame.maxY {
                frame.origin.y = visibleFrame.maxY - frame.height
            }
            if frame.minY < visibleFrame.minY {
                frame.origin.y = visibleFrame.minY
            }
        }

        window.setFrame(frame, display: true, animate: animate)
    }

    private func applyPreferencesResizeConstraints(to window: NSWindow, layoutMode: PreferencesLayoutMode) {
        let contentWidth = preferencesContentSize(for: layoutMode).width
        let maximumContentHeight = preferencesMaximumContentHeight(for: window)
        let minContentSize = NSSize(width: contentWidth, height: preferencesMinimumContentHeight)
        let maxContentSize = NSSize(
            width: contentWidth,
            height: max(maximumContentHeight, preferencesMinimumContentHeight)
        )

        window.contentMinSize = minContentSize
        window.contentMaxSize = maxContentSize
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minContentSize)).size
        window.maxSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: maxContentSize)).size
    }

    private func constrainedPreferencesFrameSize(for window: NSWindow, proposedFrameSize: NSSize) -> NSSize {
        let contentWidth = preferencesContentSize(for: preferencesLayoutMode).width
        let proposedContentHeight = window.contentRect(
            forFrameRect: NSRect(origin: .zero, size: proposedFrameSize)
        ).height
        let contentHeight = min(
            max(proposedContentHeight, preferencesMinimumContentHeight),
            preferencesMaximumContentHeight(for: window)
        )
        let contentSize = NSSize(width: contentWidth, height: contentHeight)
        return window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
    }

    private func makePreferencesContentController(
        hostingController: NSHostingController<PreferencesView>,
        initialContentSize: NSSize
    ) -> NSViewController {
        let containerController = NSViewController()
        let containerView = NSView(frame: NSRect(origin: .zero, size: initialContentSize))
        containerController.view = containerView

        containerController.addChild(hostingController)
        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostedView)

        let bottomHandle = PreferencesVerticalResizeHandleView(edge: .bottom)
        bottomHandle.translatesAutoresizingMaskIntoConstraints = false
        bottomHandle.resizeBegan = { [weak self] initialFrame in
            self?.beginPreferencesWindowResize(initialFrame: initialFrame)
        }
        bottomHandle.resizeChanged = { [weak self] initialFrame, deltaY in
            self?.queuePreferencesWindowResizeFromBottom(initialFrame: initialFrame, deltaY: deltaY)
        }
        bottomHandle.resizeEnded = { [weak self] in
            self?.endPreferencesWindowResize()
        }
        containerView.addSubview(bottomHandle)

        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            bottomHandle.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            bottomHandle.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            bottomHandle.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            bottomHandle.heightAnchor.constraint(equalToConstant: PreferencesVerticalResizeHandleView.handleThickness)
        ])

        return containerController
    }

    private func beginPreferencesWindowResize(initialFrame: NSRect) {
        guard let window = preferencesWindow else { return }
        applyPreferencesResizeConstraints(to: window, layoutMode: preferencesLayoutMode)

        preferencesWindowWasMovableByBackground = window.isMovableByWindowBackground
        window.isMovableByWindowBackground = false
        window.contentView?.viewWillStartLiveResize()
        preferencesResizeState = PreferencesResizeState(initialFrame: initialFrame, deltaY: 0, appliedFrame: nil)
        startPreferencesResizeTimer()
    }

    private func queuePreferencesWindowResizeFromBottom(initialFrame: NSRect, deltaY: CGFloat) {
        if preferencesResizeState == nil {
            beginPreferencesWindowResize(initialFrame: initialFrame)
        }
        preferencesResizeState?.deltaY = deltaY
    }

    private func flushQueuedPreferencesResize(display: Bool = false) {
        guard let window = preferencesWindow,
              var state = preferencesResizeState
        else { return }

        let frame = preferencesWindowResizeFrameFromBottom(
            for: window,
            initialFrame: state.initialFrame,
            deltaY: state.deltaY
        )
        guard state.appliedFrame != frame else { return }

        state.appliedFrame = frame
        preferencesResizeState = state
        window.setFrame(frame, display: display)
        if !display {
            window.contentView?.needsLayout = true
            window.contentView?.needsDisplay = true
        }
    }

    private func endPreferencesWindowResize() {
        guard preferencesResizeState != nil else { return }
        flushQueuedPreferencesResize(display: true)
        preferencesResizeTimer?.invalidate()
        preferencesResizeTimer = nil

        if let window = preferencesWindow {
            window.contentView?.viewDidEndLiveResize()
            window.isMovableByWindowBackground = preferencesWindowWasMovableByBackground
        }
        preferencesResizeState = nil
    }

    private func startPreferencesResizeTimer() {
        preferencesResizeTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.flushQueuedPreferencesResize()
        }
        timer.tolerance = 1.0 / 240.0
        preferencesResizeTimer = timer
        RunLoop.main.add(timer, forMode: .default)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func preferencesWindowResizeFrameFromBottom(
        for window: NSWindow,
        initialFrame: NSRect,
        deltaY: CGFloat
    ) -> NSRect {
        let proposedHeight = initialFrame.height - deltaY
        let maximumHeight = min(
            window.maxSize.height,
            maximumPreferencesFrameHeightFromBottom(for: window, initialFrame: initialFrame)
        )
        let targetHeight = pixelAligned(
            min(max(proposedHeight, window.minSize.height), maximumHeight),
            for: window
        )
        let targetSize = constrainedPreferencesFrameSize(
            for: window,
            proposedFrameSize: NSSize(width: initialFrame.width, height: targetHeight)
        )
        var frame = initialFrame
        frame.size = targetSize
        frame.origin.x = initialFrame.minX
        frame.origin.y = initialFrame.maxY - targetSize.height

        return frame
    }

    private func pixelAligned(_ value: CGFloat, for window: NSWindow) -> CGFloat {
        let scale = max(window.backingScaleFactor, 1)
        return (value * scale).rounded() / scale
    }

    private func maximumPreferencesFrameHeightFromBottom(
        for window: NSWindow,
        initialFrame: NSRect
    ) -> CGFloat {
        guard let screen = window.screen ?? Self.preferredScreenForPreferences() else {
            return CGFloat.greatestFiniteMagnitude
        }
        let visibleFrame = screen.visibleFrame.insetBy(dx: 18, dy: 18)
        return max(window.minSize.height, initialFrame.maxY - visibleFrame.minY)
    }

    private func preferencesMaximumContentHeight(for window: NSWindow) -> CGFloat {
        guard let screen = window.screen ?? Self.preferredScreenForPreferences() else {
            return CGFloat.greatestFiniteMagnitude
        }
        let visibleFrame = screen.visibleFrame.insetBy(dx: 18, dy: 18)
        return window.contentRect(forFrameRect: NSRect(origin: .zero, size: visibleFrame.size)).height
    }

    private func initialPreferencesLayoutMode() -> PreferencesLayoutMode {
        if store.preferredPreferencesTab == "customize" {
            return store.preferredCustomizeKind == nil ? .compact : .detail
        }
        return .compact
    }

    private func preferencesContentSize(for layoutMode: PreferencesLayoutMode) -> NSSize {
        switch layoutMode {
        case .compact:
            return preferencesCompactContentSize
        case .detail:
            return preferencesExpandedContentSize
        }
    }

    private func centerPreferencesWindow(_ window: NSWindow) {
        guard let screen = Self.preferredScreenForPreferences() else { return }
        let visibleFrame = screen.visibleFrame.insetBy(dx: 18, dy: 18)
        var frame = window.frame
        frame.size.width = min(frame.width, visibleFrame.width)
        frame.size.height = min(frame.height, visibleFrame.height)
        let origin = NSPoint(
            x: visibleFrame.minX + max((visibleFrame.width - frame.width) / 2, 0),
            y: visibleFrame.minY + max((visibleFrame.height - frame.height) / 2, 0)
        )
        frame.origin = origin
        window.setFrame(frame, display: true)
    }

    private func keepPreferencesWindowVisible(_ window: NSWindow) {
        guard let screen = Self.preferredScreenForPreferences() else { return }
        applyPreferencesResizeConstraints(to: window, layoutMode: preferencesLayoutMode)
        let visibleFrame = screen.visibleFrame.insetBy(dx: 18, dy: 18)
        var frame = window.frame
        frame.size.width = min(frame.width, visibleFrame.width)
        frame.size.height = min(frame.height, visibleFrame.height)

        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width
        }
        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX
        }
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height
        }
        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY
        }

        window.setFrame(frame, display: true)
    }

    private static func preferredScreenForPreferences() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return mouseScreen
        }
        if let mainScreen = NSScreen.main {
            return mainScreen
        }
        return NSScreen.screens.first
    }

    @objc private func quit() {
        store.quit()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openPreferences()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        endPreferencesWindowResize()
        store.prepareForTermination()
        removeDashboardEventMonitors()
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === preferencesWindow {
            endPreferencesWindowResize()
            preferencesWindow = nil
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === preferencesWindow else { return frameSize }
        return constrainedPreferencesFrameSize(for: sender, proposedFrameSize: frameSize)
    }

    private func updateStatusIcon(_ icon: MenuBarIcon) {
        guard let button = statusItem?.button else { return }
        let image = icon.templateImage()
        button.image = image
        button.imagePosition = .imageOnly
    }

    private func showDashboard(relativeTo button: NSStatusBarButton) {
        let window = dashboardWindow ?? makeDashboardWindow()
        dashboardWindow = window
        resetDashboardTransientState()
        let size = currentDashboardSize
        window.setContentSize(size)
        window.setFrameOrigin(dashboardOrigin(relativeTo: button, size: size))
        window.orderFrontRegardless()
        window.makeKey()
        installDashboardEventMonitors()
        scheduleDashboardRefreshAfterOpen()
    }

    private func hideDashboard() {
        resetDashboardTransientState()
        dashboardWindow?.orderOut(nil)
        removeDashboardEventMonitors()
    }

    private func resetDashboardTransientState() {
        NotificationCenter.default.post(name: .resetMacSwitchDashboardTransientState, object: nil)
    }

    private func makeDashboardWindow() -> DashboardPanel {
        let window = DashboardPanel(
            contentRect: NSRect(origin: .zero, size: currentDashboardSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: DashboardView(store: store))
        configureDashboardRoundedMask(on: hostingView)
        window.contentView = hostingView
        window.title = "Dashboard"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        configureDashboardRoundedMask(on: window.contentView)
        configureDashboardRoundedMask(on: window.contentView?.superview)
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.animationBehavior = .utilityWindow
        return window
    }

    private func configureDashboardRoundedMask(on view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
        view.layer?.cornerRadius = DashboardLayout.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }

    private func prewarmDashboard() {
        guard dashboardWindow == nil else { return }
        dashboardWindow = makeDashboardWindow()
    }

    private func showDashboardForSmokeTest() {
        let window = dashboardWindow ?? makeDashboardWindow()
        dashboardWindow = window
        resetDashboardTransientState()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let size = currentDashboardSize
        window.setContentSize(size)
        let origin = NSPoint(
            x: min(visibleFrame.midX - size.width / 2, visibleFrame.maxX - size.width - 8),
            y: min(visibleFrame.midY - size.height / 2, visibleFrame.maxY - size.height - 8)
        )
        window.setFrameOrigin(NSPoint(x: max(origin.x, visibleFrame.minX + 8), y: max(origin.y, visibleFrame.minY + 8)))
        window.orderFrontRegardless()
        window.makeKey()
        store.refreshVisibleAsync()
    }

    private func scheduleDashboardRefreshAfterOpen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self, self.dashboardWindow?.isVisible == true else { return }
            self.store.refreshVisibleAsync()
        }
    }

    private func finishUISmokeTest() {
        let result: UISmokeResult
        if Self.dashboardSmokeMode {
            result = UISmokeDiagnostics.evaluateCurrentProcess(
                windowTitle: "Dashboard",
                sectionTitle: "Dashboard UI Smoke",
                minimumSize: currentDashboardSize
            )
        } else {
            result = UISmokeDiagnostics.evaluateCurrentProcess(
                windowTitle: "Preferences",
                sectionTitle: "Preferences UI Smoke",
                minimumSize: preferencesContentSize(for: preferencesLayoutMode)
            )
        }
        print(result.output)
        fflush(stdout)
        Darwin.exit(result.passed ? 0 : 1)
    }

    private var currentDashboardSize: NSSize {
        DashboardLayout.size(
            visibleCount: store.visibleKinds.count,
            visibleModeCount: store.visibleModes.count,
            showsError: store.lastError != nil
        )
    }

    private func dashboardOrigin(relativeTo button: NSStatusBarButton, size: NSSize) -> NSPoint {
        guard let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else {
            return .zero
        }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visibleFrame = screen.visibleFrame
        let x = min(max(buttonFrame.midX - size.width / 2, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        let y = buttonFrame.minY - size.height - 8
        return NSPoint(x: x, y: max(y, visibleFrame.minY + 8))
    }

    private func resizeVisibleDashboardKeepingTopEdge() {
        guard let window = dashboardWindow, window.isVisible else { return }
        let size = currentDashboardSize
        let frame = window.frame
        let origin = NSPoint(x: frame.minX, y: frame.maxY - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    private func installDashboardEventMonitors() {
        guard dashboardLocalEventMonitor == nil, dashboardGlobalEventMonitor == nil else { return }

        dashboardLocalEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                self.hideDashboard()
                return nil
            }

            if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
                let clickedDashboard = event.window === self.dashboardWindow
                if !clickedDashboard && !self.eventHitsStatusItem(event) {
                    self.hideDashboard()
                }
            }

            return event
        }

        dashboardGlobalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.hideDashboard()
        }
    }

    private func removeDashboardEventMonitors() {
        if let dashboardLocalEventMonitor {
            NSEvent.removeMonitor(dashboardLocalEventMonitor)
            self.dashboardLocalEventMonitor = nil
        }

        if let dashboardGlobalEventMonitor {
            NSEvent.removeMonitor(dashboardGlobalEventMonitor)
            self.dashboardGlobalEventMonitor = nil
        }
    }

    private func eventHitsStatusItem(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button,
              let buttonWindow = button.window,
              event.window === buttonWindow else {
            return false
        }

        let eventPoint = buttonWindow.convertPoint(toScreen: event.locationInWindow)
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil)).insetBy(dx: -4, dy: -4)
        return buttonFrame.contains(eventPoint)
    }
}

private enum PreferencesVerticalResizeEdge {
    case bottom
}

private final class PreferencesVerticalResizeHandleView: NSView {
    static let handleThickness: CGFloat = 8
    private static let verticalResizeCursor = NSCursor(
        image: verticalResizeCursorImage(),
        hotSpot: NSPoint(x: 8, y: 11)
    )

    let edge: PreferencesVerticalResizeEdge
    var resizeBegan: ((NSRect) -> Void)?
    var resizeChanged: ((NSRect, CGFloat) -> Void)?
    var resizeEnded: (() -> Void)?
    private var initialMouseY: CGFloat = 0
    private var initialFrame: NSRect = .zero
    private var isDragging = false

    init(edge: PreferencesVerticalResizeEdge) {
        self.edge = edge
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: Self.verticalResizeCursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialMouseY = NSEvent.mouseLocation.y
        initialFrame = window.frame
        isDragging = true
        resizeBegan?(initialFrame)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let deltaY = NSEvent.mouseLocation.y - initialMouseY
        resizeChanged?(initialFrame, deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        let deltaY = NSEvent.mouseLocation.y - initialMouseY
        resizeChanged?(initialFrame, deltaY)
        resizeEnded?()
    }

    private static func verticalResizeCursorImage() -> NSImage {
        let size = NSSize(width: 16, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.white.setStroke()
        let outline = NSBezierPath()
        outline.lineWidth = 3.5
        outline.lineCapStyle = .round
        outline.lineJoinStyle = .round
        drawVerticalResizeCursor(in: outline)
        outline.stroke()

        NSColor.black.setStroke()
        let glyph = NSBezierPath()
        glyph.lineWidth = 1.8
        glyph.lineCapStyle = .round
        glyph.lineJoinStyle = .round
        drawVerticalResizeCursor(in: glyph)
        glyph.stroke()

        image.unlockFocus()
        return image
    }

    private static func drawVerticalResizeCursor(in path: NSBezierPath) {
        path.move(to: NSPoint(x: 8, y: 2.5))
        path.line(to: NSPoint(x: 8, y: 19.5))

        path.move(to: NSPoint(x: 4.5, y: 16))
        path.line(to: NSPoint(x: 8, y: 19.5))
        path.line(to: NSPoint(x: 11.5, y: 16))

        path.move(to: NSPoint(x: 4.5, y: 6))
        path.line(to: NSPoint(x: 8, y: 2.5))
        path.line(to: NSPoint(x: 11.5, y: 6))
    }
}

final class DashboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct UISmokeResult {
    let passed: Bool
    let output: String
}

private enum UISmokeDiagnostics {
    static func evaluateCurrentProcess(
        windowTitle: String,
        sectionTitle: String,
        minimumSize: NSSize
    ) -> UISmokeResult {
        var reporter = UISmokeReporter()
        reporter.section(sectionTitle)

        let windows = currentProcessWindows()
        let targetWindow = windows.first { windowName($0) == windowTitle }
        reporter.check(targetWindow != nil, "\(windowTitle) window exists")

        if let targetWindow {
            let onscreen = isOnscreen(targetWindow)
            reporter.check(onscreen, "\(windowTitle) window is onscreen")

            let size = windowSize(targetWindow)
            reporter.check(
                size.width >= minimumSize.width && size.height >= minimumSize.height,
                "\(windowTitle) window size is \(Int(size.width))x\(Int(size.height))"
            )
        }

        return UISmokeResult(passed: !reporter.hasFailures, output: reporter.output)
    }

    private static func currentProcessWindows() -> [[String: Any]] {
        let pid = Int(getpid())
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        return (windows ?? []).filter { ownerPID($0) == pid }
    }

    private static func ownerPID(_ window: [String: Any]) -> Int? {
        if let value = window[kCGWindowOwnerPID as String] as? Int {
            return value
        }
        if let value = window[kCGWindowOwnerPID as String] as? Int32 {
            return Int(value)
        }
        return nil
    }

    private static func windowName(_ window: [String: Any]) -> String {
        window[kCGWindowName as String] as? String ?? ""
    }

    private static func isOnscreen(_ window: [String: Any]) -> Bool {
        if let value = window[kCGWindowIsOnscreen as String] as? Bool {
            return value
        }
        if let value = window[kCGWindowIsOnscreen as String] as? Int {
            return value != 0
        }
        return false
    }

    private static func windowSize(_ window: [String: Any]) -> CGSize {
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any] else { return .zero }
        return CGSize(width: number(bounds["Width"]), height: number(bounds["Height"]))
    }

    private static func number(_ value: Any?) -> CGFloat {
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Int { return CGFloat(value) }
        return 0
    }
}

private struct UISmokeReporter {
    private(set) var hasFailures = false
    private(set) var lines: [String] = []

    var output: String {
        (lines + ["", "Result: \(hasFailures ? "FAIL" : "PASS")"]).joined(separator: "\n")
    }

    mutating func section(_ title: String) {
        lines.append("## \(title)")
    }

    mutating func check(_ condition: Bool, _ message: String) {
        if condition {
            lines.append("PASS \(message)")
        } else {
            hasFailures = true
            lines.append("FAIL \(message)")
        }
    }
}
