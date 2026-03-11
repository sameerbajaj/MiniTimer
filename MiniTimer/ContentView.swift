//
//  ContentView.swift
//  MiniTimer
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var viewModel = StopwatchViewModel()
    @State private var isHovering = false
    @State private var showingResetConfirmation = false
    @State private var showCopiedFeedback = false
    @State private var updateStatusMessage: String?

    var body: some View {
        GeometryReader { geometry in
            let metrics = LayoutMetrics(size: geometry.size)

            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .ignoresSafeArea()

                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .fill(.white.opacity(metrics.backgroundOpacity))
                    .overlay {
                        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
                    .padding(metrics.outerPadding)

                VStack(spacing: metrics.sectionSpacing) {
                    topBar(compact: metrics.isCompact)

                    if viewModel.isInstallingUpdate {
                        installBanner(compact: metrics.isCompact)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else if let updateInfo = viewModel.updateInfo {
                        updateBanner(updateInfo: updateInfo, compact: metrics.isCompact)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else if let updateStatusMessage {
                        updateStatusBanner(message: updateStatusMessage)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer(minLength: 0)

                    timeDisplay(metrics: metrics)

                    statusRow(compact: metrics.isCompact)

                    controlRow(metrics: metrics)

                    bottomBar(compact: metrics.isCompact)

                    Spacer(minLength: 0)
                }
                .padding(metrics.contentPadding)
            }
            .background(WindowDragView())
        }
        .frame(minWidth: 220, idealWidth: 340, minHeight: 180, idealHeight: 260)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
        .onAppear {
            viewModel.checkUpdates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .miniTimerCheckForUpdates)) { _ in
            checkForUpdatesManually()
        }
        .onChange(of: viewModel.updateErrorMessage) { _, newValue in
            guard let newValue else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                updateStatusMessage = newValue
            }
        }
        .alert("Reset timer?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                viewModel.reset()
            }
        } message: {
            Text(viewModel.timeElapsed > 0 ? "This will clear the current elapsed time." : "The timer is already at zero.")
        }
    }

    @ViewBuilder
    private func topBar(compact: Bool) -> some View {
        HStack(spacing: 10) {
            Label {
                if !compact {
                    Text("MiniTimer")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            } icon: {
                Circle()
                    .fill(viewModel.isRunning ? Color.green : Color.secondary.opacity(0.55))
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle()
                            .stroke(viewModel.isRunning ? .green.opacity(0.35) : .clear, lineWidth: 6)
                            .scaleEffect(viewModel.isRunning ? 1.05 : 1)
                            .opacity(viewModel.isRunning ? 0.35 : 0)
                    }
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: viewModel.isRunning)
            }
            .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 8) {
                utilityButton(
                    systemName: viewModel.isCheckingForUpdates ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath",
                    accessibilityLabel: "Check for updates",
                    isActive: viewModel.isCheckingForUpdates
                ) {
                    checkForUpdatesManually()
                }
                .help(viewModel.isCheckingForUpdates ? "Checking for Updates…" : "Check for Updates")

                utilityButton(
                    systemName: viewModel.isAlwaysOnTop ? "pin.fill" : "pin",
                    accessibilityLabel: viewModel.isAlwaysOnTop ? "Disable always on top" : "Enable always on top",
                    isActive: viewModel.isAlwaysOnTop
                ) {
                    viewModel.isAlwaysOnTop.toggle()
                }
                .help(viewModel.isAlwaysOnTop ? "Always on Top Enabled" : "Keep Window on Top")

                utilityButton(
                    systemName: "doc.on.doc",
                    accessibilityLabel: "Copy current time"
                ) {
                    copyCurrentTime()
                }
                .help(showCopiedFeedback ? "Copied" : "Copy Time")

                utilityButton(
                    systemName: "xmark",
                    accessibilityLabel: "Quit MiniTimer",
                    prominence: .subtle
                ) {
                    NSApplication.shared.terminate(nil)
                }
                .help("Quit")
                .opacity(isHovering || compact ? 1 : 0.72)
            }
        }
    }

    @ViewBuilder
    private func timeDisplay(metrics: LayoutMetrics) -> some View {
        VStack(spacing: max(6, metrics.sectionSpacing * 0.35)) {
            Text(viewModel.formattedPrimaryTime)
                .font(.system(size: metrics.timeFontSize, weight: .thin, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Text(viewModel.formattedFractionalTime)
                .font(.system(size: metrics.fractionFontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel("Tenths of a second \(viewModel.formattedFractionalTime)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.timePadding)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func statusRow(compact: Bool) -> some View {
        HStack(spacing: 10) {
            statusPill(
                title: viewModel.isRunning ? "Running" : "Paused",
                systemName: viewModel.isRunning ? "play.fill" : "pause.fill",
                tint: viewModel.isRunning ? .green : .secondary
            )

            statusPill(
                title: viewModel.isAlwaysOnTop ? "Pinned" : "Normal",
                systemName: viewModel.isAlwaysOnTop ? "pin.fill" : "macwindow",
                tint: viewModel.isAlwaysOnTop ? .blue : .secondary
            )

            if viewModel.isInstallingUpdate {
                statusPill(
                    title: "Installing",
                    systemName: "square.and.arrow.down.fill",
                    tint: .orange
                )
            } else if viewModel.isCheckingForUpdates {
                statusPill(
                    title: "Checking",
                    systemName: "arrow.triangle.2.circlepath",
                    tint: .teal
                )
            }

            Spacer(minLength: 0)

            if !compact {
                Text(viewModel.shortHintText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func controlRow(metrics: LayoutMetrics) -> some View {
        if metrics.isVeryCompact {
            VStack(spacing: 10) {
                primaryActionButton(compact: true)
                secondaryControls(compact: true)
            }
        } else {
            HStack(spacing: 12) {
                secondaryResetButton()

                primaryActionButton(compact: false)

                secondaryControls(compact: false)
            }
        }
    }

    @ViewBuilder
    private func secondaryControls(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 10) {
            utilityActionButton(
                title: "Lap",
                systemName: "flag.fill",
                isEnabled: viewModel.timeElapsed > 0 && !viewModel.isInstallingUpdate
            ) {
                copyCurrentTime()
            }

            utilityActionButton(
                title: updatesButtonTitle,
                systemName: updatesButtonSymbol,
                isEnabled: !viewModel.isInstallingUpdate
            ) {
                updatesPrimaryAction()
            }

            utilityActionButton(
                title: "Reset",
                systemName: "arrow.counterclockwise",
                isEnabled: !viewModel.isInstallingUpdate
            ) {
                showingResetConfirmation = true
            }
        }
    }

    @ViewBuilder
    private func secondaryResetButton() -> some View {
        Button {
            showingResetConfirmation = true
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(viewModel.timeElapsed > 0 && !viewModel.isInstallingUpdate ? .primary : .secondary)
        .disabled(viewModel.isInstallingUpdate)
        .help("Reset")
        .accessibilityLabel("Reset timer")
    }

    @ViewBuilder
    private func primaryActionButton(compact: Bool) -> some View {
        Button {
            viewModel.toggleTimer()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: compact ? 17 : 18, weight: .bold))

                Text(viewModel.isRunning ? "Pause" : "Start")
                    .font(.system(size: compact ? 16 : 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: compact ? .infinity : 150)
            .frame(height: compact ? 48 : 52)
            .background(
                LinearGradient(
                    colors: viewModel.isRunning
                        ? [Color.orange, Color.orange.opacity(0.8)]
                        : [Color.accentColor, Color.accentColor.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(
                color: (viewModel.isRunning ? Color.orange : Color.accentColor).opacity(0.28),
                radius: 14,
                y: 8
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .help(viewModel.isRunning ? "Pause" : "Start")
        .accessibilityLabel(viewModel.isRunning ? "Pause timer" : "Start timer")
        .disabled(viewModel.isInstallingUpdate)
    }

    @ViewBuilder
    private func bottomBar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                updatesPrimaryAction()
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isCheckingForUpdates || viewModel.isInstallingUpdate {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }

                    Text(bottomBarUpdateText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle((viewModel.isCheckingForUpdates || viewModel.isInstallingUpdate) ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isInstallingUpdate)
            .help(bottomBarUpdateHelp)

            Spacer()

            if showCopiedFeedback {
                Label("Copied", systemImage: "checkmark")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            Button {
                NSWorkspace.shared.open(UpdateChecker.releasesPage)
            } label: {
                HStack(spacing: 4) {
                    if viewModel.updateInfo != nil {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                    }

                    Text("v\(UpdateChecker.currentVersion)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(viewModel.updateInfo != nil ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(viewModel.updateInfo != nil ? "View update" : "View releases")
        }
        .animation(.easeInOut(duration: 0.2), value: showCopiedFeedback)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isCheckingForUpdates)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isInstallingUpdate)
    }

    @ViewBuilder
    private func updateBanner(updateInfo: UpdateInfo, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Update available")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Version \(updateInfo.version) is ready to install.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(compact ? 2 : 1)
            }

            Spacer(minLength: 8)

            Button("Install") {
                installUpdate()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.white)
            .disabled(viewModel.isInstallingUpdate)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.updateInfo = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 24, height: 24)
                    .background(.black.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss update notice")
            .disabled(viewModel.isInstallingUpdate)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.92), Color.teal.opacity(0.88)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    @ViewBuilder
    private func installBanner(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "square.and.arrow.down.fill")
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text(installPhaseTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 6) {
                    Text(installProgressText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(compact ? 2 : 1)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.2))

                            Capsule()
                                .fill(.white)
                                .frame(width: max(10, proxy.size.width * CGFloat(viewModel.installProgress.clamped(to: 0...1))))
                        }
                    }
                    .frame(height: 6)
                }
            }

            Spacer(minLength: 8)

            Text(progressPercentageText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.94), Color.red.opacity(0.86)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    @ViewBuilder
    private func updateStatusBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    updateStatusMessage = nil
                    viewModel.clearUpdateError()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 24, height: 24)
                    .background(.black.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss update status")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.92), Color.indigo.opacity(0.88)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    @ViewBuilder
    private func statusPill(title: String, systemName: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
            Text(title)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func utilityButton(
        systemName: String,
        accessibilityLabel: String,
        prominence: UtilityProminence = .regular,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : (prominence == .subtle ? .secondary : .primary))
                .frame(width: 30, height: 30)
                .background(
                    Group {
                        if isActive {
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.16))
                        } else {
                            Capsule(style: .continuous)
                                .fill(.white.opacity(prominence == .subtle ? 0.05 : 0.08))
                        }
                    }
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .disabled(
            (viewModel.isCheckingForUpdates && accessibilityLabel == "Check for updates") ||
            viewModel.isInstallingUpdate
        )
    }

    @ViewBuilder
    private func utilityActionButton(
        title: String,
        systemName: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? .primary : .secondary)
    }

    private var updatesButtonTitle: String {
        if viewModel.isInstallingUpdate {
            return "Installing…"
        }
        if viewModel.updateInfo != nil {
            return "Install"
        }
        if viewModel.isCheckingForUpdates {
            return "Checking…"
        }
        return "Updates"
    }

    private var updatesButtonSymbol: String {
        if viewModel.isInstallingUpdate {
            return "square.and.arrow.down.fill"
        }
        if viewModel.updateInfo != nil {
            return "arrow.down.app.fill"
        }
        if viewModel.isCheckingForUpdates {
            return "arrow.triangle.2.circlepath.circle.fill"
        }
        return "arrow.down.circle"
    }

    private var bottomBarUpdateText: String {
        if viewModel.isInstallingUpdate {
            return installProgressText
        }
        if viewModel.updateInfo != nil {
            return "Install update"
        }
        if viewModel.isCheckingForUpdates {
            return "Checking for updates…"
        }
        return "Check for updates"
    }

    private var bottomBarUpdateHelp: String {
        if viewModel.isInstallingUpdate {
            return "Installing update"
        }
        if viewModel.updateInfo != nil {
            return "Install the available update"
        }
        return "Manually check for updates"
    }

    private var installPhaseTitle: String {
        if viewModel.installPhaseDescription.isEmpty {
            return "Installing update"
        }
        return "Installing update"
    }

    private var installProgressText: String {
        if !viewModel.installPhaseDescription.isEmpty {
            return viewModel.installPhaseDescription
        }

        if viewModel.installProgress > 0, viewModel.installProgress < 1 {
            return "Downloading update…"
        }

        return "Preparing update…"
    }

    private var progressPercentageText: String {
        "\(Int((viewModel.installProgress.clamped(to: 0...1) * 100).rounded()))%"
    }

    private func copyCurrentTime() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(viewModel.accessibilityFormattedTime, forType: .string)

        withAnimation(.easeInOut(duration: 0.18)) {
            showCopiedFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.18)) {
                showCopiedFeedback = false
            }
        }
    }

    private func checkForUpdatesManually() {
        guard !viewModel.isCheckingForUpdates, !viewModel.isInstallingUpdate else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            updateStatusMessage = nil
            viewModel.clearUpdateError()
        }

        viewModel.manuallyCheckForUpdates()
    }

    private func installUpdate() {
        guard viewModel.updateInfo != nil, !viewModel.isInstallingUpdate else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            updateStatusMessage = nil
            viewModel.clearUpdateError()
        }

        viewModel.installAvailableUpdate()
    }

    private func updatesPrimaryAction() {
        if viewModel.updateInfo != nil {
            installUpdate()
        } else {
            checkForUpdatesManually()
        }
    }
}

private enum UtilityProminence {
    case regular
    case subtle
}

private struct LayoutMetrics {
    let size: CGSize

    var isVeryCompact: Bool {
        size.width < 290 || size.height < 210
    }

    var isCompact: Bool {
        size.width < 340 || size.height < 235
    }

    var outerPadding: CGFloat {
        isVeryCompact ? 8 : 10
    }

    var contentPadding: CGFloat {
        isVeryCompact ? 14 : 18
    }

    var sectionSpacing: CGFloat {
        isVeryCompact ? 12 : 16
    }

    var cornerRadius: CGFloat {
        isVeryCompact ? 18 : 22
    }

    var backgroundOpacity: Double {
        isVeryCompact ? 0.05 : 0.07
    }

    var timePadding: CGFloat {
        isVeryCompact ? 4 : 10
    }

    var timeFontSize: CGFloat {
        min(max(size.width * 0.24, 42), isCompact ? 70 : 92)
    }

    var fractionFontSize: CGFloat {
        min(max(size.width * 0.08, 14), isCompact ? 22 : 28)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// Background blur effect
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableNSView {
        DraggableNSView()
    }

    func updateNSView(_ nsView: DraggableNSView, context: Context) {}
}

class DraggableNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

#Preview {
    ContentView()
}
