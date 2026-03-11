//
//  StopwatchViewModel.swift
//  MiniTimer
//

import SwiftUI
import Observation
import AppKit

@Observable
final class StopwatchViewModel {
    var timeElapsed: TimeInterval = 0
    var isRunning = false
    var isAlwaysOnTop: Bool = UserDefaults.standard.bool(forKey: "isAlwaysOnTop") {
        didSet {
            UserDefaults.standard.set(isAlwaysOnTop, forKey: "isAlwaysOnTop")
            updateWindowLevel()
        }
    }
    
    var updateInfo: UpdateInfo?
    private var timer: Timer?
    
    init() {
        // Initial window level setup
        DispatchQueue.main.async {
            self.updateWindowLevel()
        }
    }
    
    func toggleTimer() {
        if isRunning {
            stopTimer()
        } else {
            startTimer()
        }
    }
    
    private func startTimer() {
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.timeElapsed += 0.1
            }
        }
    }
    
    private func stopTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    func reset() {
        stopTimer()
        timeElapsed = 0
    }
    
    func updateWindowLevel() {
        if let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.delegate != nil }) ?? NSApplication.shared.keyWindow {
            window.level = isAlwaysOnTop ? .floating : .normal
        }
    }
    
    func checkUpdates() {
        Task {
            if let info = await UpdateChecker.check() {
                await MainActor.run {
                    self.updateInfo = info
                }
            }
        }
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
