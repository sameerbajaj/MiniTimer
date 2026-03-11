//
//  ContentView.swift
//  MiniTimer
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var viewModel = StopwatchViewModel()

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                timeDisplay
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                controlRow
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(WindowDragView())
        .onAppear {
            viewModel.checkUpdates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .miniTimerCheckForUpdates)) { _ in
            viewModel.manuallyCheckForUpdates()
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
                .animation(.easeInOut(duration: 0.25), value: viewModel.isRunning)

            Text("MiniTimer")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                viewModel.isAlwaysOnTop.toggle()
            } label: {
                Image(systemName: viewModel.isAlwaysOnTop ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(viewModel.isAlwaysOnTop ? Color.accentColor : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(viewModel.isAlwaysOnTop ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help(viewModel.isAlwaysOnTop ? "Unpin window" : "Keep on top")
            .accessibilityLabel(viewModel.isAlwaysOnTop ? "Unpin window" : "Pin window on top")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Quit MiniTimer")
            .accessibilityLabel("Quit MiniTimer")
        }
    }

    // MARK: - Time Display

    private var timeDisplay: some View {
        Text("\(viewModel.formattedPrimaryTime)\(viewModel.formattedFractionalTime)")
            .font(.system(size: 54, weight: .thin, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(viewModel.accessibilityFormattedTime)
    }

    // MARK: - Controls

    private var controlRow: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(viewModel.timeElapsed > 0 || viewModel.isRunning ? Color.primary : Color.secondary)
                    .frame(width: 42, height: 38)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Reset")
            .accessibilityLabel("Reset timer")

            Button {
                viewModel.toggleTimer()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(viewModel.isRunning ? "Pause" : "Start")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    viewModel.isRunning ? Color.orange : Color.accentColor,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .help(viewModel.isRunning ? "Pause timer" : "Start timer")
            .accessibilityLabel(viewModel.isRunning ? "Pause timer" : "Start timer")
        }
    }
}

// MARK: - Supporting Views

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
