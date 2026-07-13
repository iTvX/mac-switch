import AppKit
import Combine
import CoreGraphics
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private enum PreferencesLayoutMode: String {
        case compact
        case detail
    }

    private let preferencesCompactContentSize = NSSize(width: 580, height: 440)
    private let preferencesExpandedContentSize = NSSize(width: 980, height: 460)
    private let preferencesMinimumContentHeight: CGFloat = 320
    private let statusItemWidth: CGFloat = 20
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
        let edge: PreferencesVerticalResizeEdge
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

        let item = NSStatusBar.system.statusItem(withLength: statusItemWidth)
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
        if let window = preferencesWindow {
            window.contentView?.layoutSubtreeIfNeeded()
            applyPreferencesResizeConstraints(to: window, layoutMode: preferencesLayoutMode)
        }
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
        var minFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minContentSize)).size
        minFrameSize.height = max(minFrameSize.height, preferencesMinimumFrameHeight(for: window))
        window.minSize = minFrameSize
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
        var frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        frameSize.height = max(frameSize.height, preferencesMinimumFrameHeight(for: window))
        return frameSize
    }

    private func preferencesMinimumFrameHeight(for window: NSWindow) -> CGFloat {
        let contentLayoutInset = max(window.frame.height - window.contentLayoutRect.height, 0)
        let titlebarInset = max(window.contentView?.safeAreaInsets.top ?? 0, contentLayoutInset)
        return preferencesMinimumContentHeight + titlebarInset
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

        func makeResizeHandle(for edge: PreferencesVerticalResizeEdge) -> PreferencesVerticalResizeHandleView {
            let handle = PreferencesVerticalResizeHandleView(edge: edge)
            handle.translatesAutoresizingMaskIntoConstraints = false
            handle.resizeBegan = { [weak self] initialFrame in
                self?.beginPreferencesWindowResize(edge: edge, initialFrame: initialFrame)
            }
            handle.resizeChanged = { [weak self] initialFrame, deltaY in
                self?.queuePreferencesWindowResize(edge: edge, initialFrame: initialFrame, deltaY: deltaY)
            }
            handle.resizeEnded = { [weak self] in
                self?.endPreferencesWindowResize()
            }
            containerView.addSubview(handle)
            return handle
        }
        let topHandle = makeResizeHandle(for: .top)
        let bottomHandle = makeResizeHandle(for: .bottom)

        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            topHandle.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            topHandle.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            topHandle.topAnchor.constraint(equalTo: containerView.topAnchor),
            topHandle.heightAnchor.constraint(equalToConstant: PreferencesVerticalResizeHandleView.handleThickness),
            bottomHandle.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            bottomHandle.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            bottomHandle.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            bottomHandle.heightAnchor.constraint(equalToConstant: PreferencesVerticalResizeHandleView.handleThickness)
        ])

        return containerController
    }

    private func beginPreferencesWindowResize(edge: PreferencesVerticalResizeEdge, initialFrame: NSRect) {
        guard let window = preferencesWindow else { return }
        applyPreferencesResizeConstraints(to: window, layoutMode: preferencesLayoutMode)

        preferencesWindowWasMovableByBackground = window.isMovableByWindowBackground
        window.isMovableByWindowBackground = false
        window.contentView?.viewWillStartLiveResize()
        preferencesResizeState = PreferencesResizeState(
            edge: edge,
            initialFrame: initialFrame,
            deltaY: 0,
            appliedFrame: nil
        )
        startPreferencesResizeTimer()
    }

    private func queuePreferencesWindowResize(
        edge: PreferencesVerticalResizeEdge,
        initialFrame: NSRect,
        deltaY: CGFloat
    ) {
        if let state = preferencesResizeState, state.edge != edge {
            endPreferencesWindowResize()
        }
        if preferencesResizeState == nil {
            beginPreferencesWindowResize(edge: edge, initialFrame: initialFrame)
        }
        preferencesResizeState?.deltaY = deltaY
    }

    private func flushQueuedPreferencesResize(display: Bool = false) {
        guard let window = preferencesWindow,
              var state = preferencesResizeState
        else { return }

        let frame = preferencesWindowResizeFrame(
            for: window,
            edge: state.edge,
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
            Task { @MainActor [weak self] in
                self?.flushQueuedPreferencesResize()
            }
        }
        timer.tolerance = 1.0 / 240.0
        preferencesResizeTimer = timer
        RunLoop.main.add(timer, forMode: .default)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func preferencesWindowResizeFrame(
        for window: NSWindow,
        edge: PreferencesVerticalResizeEdge,
        initialFrame: NSRect,
        deltaY: CGFloat
    ) -> NSRect {
        let proposedHeight = initialFrame.height + edge.heightDeltaMultiplier * deltaY
        let maximumHeight = min(window.maxSize.height, maximumPreferencesFrameHeight(
            for: window,
            edge: edge,
            initialFrame: initialFrame
        ))
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
        frame.origin.y = edge == .top
            ? initialFrame.minY
            : initialFrame.maxY - targetSize.height

        return frame
    }

    private func pixelAligned(_ value: CGFloat, for window: NSWindow) -> CGFloat {
        let scale = max(window.backingScaleFactor, 1)
        return (value * scale).rounded() / scale
    }

    private func maximumPreferencesFrameHeight(
        for window: NSWindow,
        edge: PreferencesVerticalResizeEdge,
        initialFrame: NSRect
    ) -> CGFloat {
        guard let screen = window.screen ?? Self.preferredScreenForPreferences() else {
            return CGFloat.greatestFiniteMagnitude
        }
        let visibleFrame = screen.visibleFrame.insetBy(dx: 18, dy: 18)
        let availableHeight = edge == .top
            ? visibleFrame.maxY - initialFrame.minY
            : initialFrame.maxY - visibleFrame.minY
        return max(window.minSize.height, availableHeight)
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
        button.imageScaling = .scaleProportionallyDown
        button.alignment = .center
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
        let resizeResult = Self.preferencesSmokeMode ? evaluatePreferencesResizeSmokeTest() : nil
        let statusItemResult = evaluateStatusItemSmokeTest()
        print(result.output)
        if let resizeResult {
            print("\n\(resizeResult.output)")
        }
        print("\n\(statusItemResult.output)")
        fflush(stdout)
        Darwin.exit(result.passed && (resizeResult?.passed ?? true) && statusItemResult.passed ? 0 : 1)
    }

    private func evaluateStatusItemSmokeTest() -> UISmokeResult {
        var reporter = UISmokeReporter()
        reporter.section("Menu Bar UI Smoke")

        guard let item = statusItem, let button = item.button else {
            reporter.check(false, "menu bar status item exists")
            return UISmokeResult(passed: false, output: reporter.output)
        }

        button.layoutSubtreeIfNeeded()
        let tolerance: CGFloat = 0.5
        reporter.check(abs(item.length - statusItemWidth) <= tolerance, "status item uses the compact width")
        reporter.check(abs(button.bounds.width - statusItemWidth) <= tolerance, "status button matches the compact width")
        reporter.check(button.image?.size == NSSize(width: 18, height: 18), "status artwork keeps its intended size")
        reporter.check(button.imagePosition == .imageOnly, "status item renders only the icon")
        reporter.check(button.alignment == .center, "status artwork stays centered")

        return UISmokeResult(passed: !reporter.hasFailures, output: reporter.output)
    }

    private func evaluatePreferencesResizeSmokeTest() -> UISmokeResult {
        var reporter = UISmokeReporter()
        reporter.section("Preferences Resize Smoke")

        guard let window = preferencesWindow else {
            reporter.check(false, "Preferences window is available for resize checks")
            return UISmokeResult(passed: false, output: reporter.output)
        }

        applyPreferencesResizeConstraints(to: window, layoutMode: preferencesLayoutMode)
        let originalFrame = window.frame
        defer { window.setFrame(originalFrame, display: true) }

        let tolerance: CGFloat = 0.5
        let minimumHeight = window.minSize.height
        reporter.check(minimumHeight > preferencesMinimumContentHeight, "minimum frame includes the titlebar safe area")

        if let contentView = window.contentView {
            contentView.layoutSubtreeIfNeeded()
            let topPoint = NSPoint(
                x: contentView.bounds.midX,
                y: contentView.bounds.maxY - PreferencesVerticalResizeHandleView.handleThickness / 2
            )
            let bottomPoint = NSPoint(
                x: contentView.bounds.midX,
                y: contentView.bounds.minY + PreferencesVerticalResizeHandleView.handleThickness / 2
            )
            let topHandle = contentView.hitTest(topPoint) as? PreferencesVerticalResizeHandleView
            let bottomHandle = contentView.hitTest(bottomPoint) as? PreferencesVerticalResizeHandleView
            reporter.check(topHandle?.edge == .top, "top edge routes events to the resize handle")
            reporter.check(bottomHandle?.edge == .bottom, "bottom edge routes events to the resize handle")

            if let topHandle,
               let pointerEvent = NSEvent.mouseEvent(
                   with: .mouseMoved,
                   location: topPoint,
                   modifierFlags: [],
                   timestamp: ProcessInfo.processInfo.systemUptime,
                   windowNumber: window.windowNumber,
                   context: nil,
                   eventNumber: 0,
                   clickCount: 0,
                   pressure: 0
               ) {
                topHandle.mouseExited(with: pointerEvent)
                let windowWasMovable = window.isMovable
                topHandle.mouseEntered(with: pointerEvent)
                reporter.check(!window.isMovable, "top edge suppresses competing titlebar movement before mouse down")
                topHandle.mouseExited(with: pointerEvent)
                reporter.check(window.isMovable == windowWasMovable, "top edge restores titlebar movement after exit")
            } else {
                reporter.check(false, "top-edge movement lifecycle is testable")
            }
        } else {
            reporter.check(false, "preferences content view is available for edge checks")
        }

        let topExpandedTarget = preferencesWindowResizeFrame(
            for: window,
            edge: .top,
            initialFrame: originalFrame,
            deltaY: 120
        )
        window.setFrame(topExpandedTarget, display: true)
        let topExpandedFrame = window.frame
        reporter.check(topExpandedFrame.height > originalFrame.height, "top edge expands the window upward")
        reporter.check(abs(topExpandedFrame.minY - originalFrame.minY) <= tolerance, "top-edge resize keeps the bottom edge fixed")
        reporter.check(abs(topExpandedFrame.width - originalFrame.width) <= tolerance, "top-edge resize keeps the width fixed")

        let topMinimumTarget = preferencesWindowResizeFrame(
            for: window,
            edge: .top,
            initialFrame: topExpandedFrame,
            deltaY: -500
        )
        window.setFrame(topMinimumTarget, display: true)
        let topMinimumFrame = window.frame
        reporter.check(abs(topMinimumFrame.height - minimumHeight) <= tolerance, "top edge stops at the real minimum height")
        reporter.check(abs(topMinimumFrame.minY - topExpandedFrame.minY) <= tolerance, "top edge cannot move the window past minimum height")

        window.setFrame(originalFrame, display: true)
        let bottomExpandedTarget = preferencesWindowResizeFrame(
            for: window,
            edge: .bottom,
            initialFrame: originalFrame,
            deltaY: -120
        )
        window.setFrame(bottomExpandedTarget, display: true)
        let bottomExpandedFrame = window.frame
        reporter.check(bottomExpandedFrame.height > originalFrame.height, "bottom edge expands the window downward")
        reporter.check(abs(bottomExpandedFrame.maxY - originalFrame.maxY) <= tolerance, "bottom-edge resize keeps the top edge fixed")
        reporter.check(abs(bottomExpandedFrame.width - originalFrame.width) <= tolerance, "bottom-edge resize keeps the width fixed")

        let bottomMinimumTarget = preferencesWindowResizeFrame(
            for: window,
            edge: .bottom,
            initialFrame: bottomExpandedFrame,
            deltaY: 500
        )
        window.setFrame(bottomMinimumTarget, display: true)
        let bottomMinimumFrame = window.frame
        reporter.check(abs(bottomMinimumFrame.height - minimumHeight) <= tolerance, "bottom edge stops at the real minimum height")
        reporter.check(abs(bottomMinimumFrame.maxY - bottomExpandedFrame.maxY) <= tolerance, "bottom edge cannot move the window past minimum height")

        return UISmokeResult(passed: !reporter.hasFailures, output: reporter.output)
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
    case top
    case bottom

    var heightDeltaMultiplier: CGFloat {
        self == .top ? 1 : -1
    }

    @available(macOS 15.0, *)
    var frameResizePosition: NSCursor.FrameResizePosition {
        self == .top ? .top : .bottom
    }
}

private final class PreferencesVerticalResizeHandleView: NSView {
    static let handleThickness: CGFloat = 8

    let edge: PreferencesVerticalResizeEdge
    var resizeBegan: ((NSRect) -> Void)?
    var resizeChanged: ((NSRect, CGFloat) -> Void)?
    var resizeEnded: (() -> Void)?
    private var initialMouseY: CGFloat = 0
    private var initialFrame: NSRect = .zero
    private var isDragging = false
    private var edgeTrackingArea: NSTrackingArea?
    private weak var movementSuppressedWindow: NSWindow?
    private var windowWasMovable = true

    init(edge: PreferencesVerticalResizeEdge) {
        self.edge = edge
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: resizeCursor)
    }

    override func updateTrackingAreas() {
        if let edgeTrackingArea {
            removeTrackingArea(edgeTrackingArea)
        }

        if edge == .top {
            let trackingArea = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            edgeTrackingArea = trackingArea
        } else {
            edgeTrackingArea = nil
        }

        super.updateTrackingAreas()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        restoreWindowMovement()
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        suppressWindowMovementForTopEdge()
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            restoreWindowMovement()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        resizeCursor.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        suppressWindowMovementForTopEdge()
        initialMouseY = NSEvent.mouseLocation.y
        initialFrame = window.frame
        isDragging = true
        resizeCursor.set()
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
        restoreWindowMovement()
    }

    deinit {
        MainActor.assumeIsolated {
            restoreWindowMovement()
        }
    }

    private func suppressWindowMovementForTopEdge() {
        guard edge == .top, let window else { return }
        if movementSuppressedWindow === window { return }

        restoreWindowMovement()
        movementSuppressedWindow = window
        windowWasMovable = window.isMovable
        window.isMovable = false
    }

    private func restoreWindowMovement() {
        guard let movementSuppressedWindow else { return }
        movementSuppressedWindow.isMovable = windowWasMovable
        self.movementSuppressedWindow = nil
    }

    private var resizeCursor: NSCursor {
        if #available(macOS 15.0, *) {
            return .frameResize(position: edge.frameResizePosition, directions: .all)
        }
        return .resizeUpDown
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
