//
//  ContentView.swift
//  MiniTimer
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var viewModel = StopwatchViewModel()
    @State private var isHovering = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                // Update Banner
                if let updateInfo = viewModel.updateInfo {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.white)
                        Text("Update available: v\(updateInfo.version)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                        Button("Download") {
                            NSWorkspace.shared.open(updateInfo.downloadURL)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.white.opacity(0.3))
                        
                        Button {
                            withAnimation {
                                viewModel.updateInfo = nil
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .transition(.move(edge: .top))
                }
                
                ZStack(alignment: .topLeading) {
                    // Close Button
                    if isHovering {
                        Button(action: { NSApplication.shared.terminate(nil) }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .transition(.opacity)
                    }
                    
                    VStack(spacing: 8) {
                        Spacer()
                        
                        // Responsive Time Display
                        GeometryReader { geo in
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Spacer()
                                Text(viewModel.formatTime(viewModel.timeElapsed))
                                    .font(.system(size: min(geo.size.width * 0.25, geo.size.height * 0.5), weight: .thin, design: .monospaced))
                                
                                Text(String(format: ".%01d", Int((viewModel.timeElapsed.truncatingRemainder(dividingBy: 1)) * 10)))
                                    .font(.system(size: min(geo.size.width * 0.12, geo.size.height * 0.25), weight: .light, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                        }
                        .frame(maxHeight: .infinity)
                        
                        // Controls
                        HStack(spacing: 24) {
                            Button(action: viewModel.reset) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.headline)
                            }
                            .buttonStyle(.plain)
                            .help("Reset")
                            
                            Button(action: viewModel.toggleTimer) {
                                Image(systemName: viewModel.isRunning ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(viewModel.isRunning ? .orange : .accentColor)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.space, modifiers: [])
                            .help(viewModel.isRunning ? "Pause" : "Start")
                            
                            Button(action: { viewModel.isAlwaysOnTop.toggle() }) {
                                Image(systemName: viewModel.isAlwaysOnTop ? "pin.fill" : "pin")
                                    .font(.headline)
                                    .foregroundColor(viewModel.isAlwaysOnTop ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Always on Top")
                        }
                        .opacity(isHovering ? 1.0 : 0.6)
                        .padding(.bottom, 12)
                        
                        Spacer()
                    }
                }
            }
        }
        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 80, maxHeight: .infinity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        .background(WindowDragView())
        .onAppear {
            viewModel.checkUpdates()
        }
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
