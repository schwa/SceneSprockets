import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

// The display's maximum frame rate and Low Power Mode, kept current as windows move between displays, displays
// change, or Low Power Mode turns on or off. SwiftUI has no API for these, so this listens to AppKit and Foundation
// notifications. Uses the main screen (the one with the key window).
@MainActor
@Observable
final class DisplayFrameRate {
    private(set) var maximumFramesPerSecond = 60
    private(set) var isLowPowerModeEnabled = false
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init() {
        update()
        var names: [Notification.Name] = [.NSProcessInfoPowerStateDidChange]
        #if canImport(AppKit)
        names += [NSApplication.didChangeScreenParametersNotification, NSWindow.didChangeScreenNotification, NSWindow.didBecomeKeyNotification]
        #endif
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.update()
                }
            }
        }
    }

    private func update() {
        #if canImport(AppKit)
        let maximum = NSScreen.main?.maximumFramesPerSecond ?? 60
        #else
        let maximum = 60
        #endif
        if maximum > 0, maximum != maximumFramesPerSecond {
            maximumFramesPerSecond = maximum
        }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if lowPower != isLowPowerModeEnabled {
            isLowPowerModeEnabled = lowPower
        }
    }

    // Caps to offer, up to the display's maximum.
    var choices: [Int] {
        [24, 30, 60, 90, 120, 144, 165, 240].filter { $0 < maximumFramesPerSecond }
    }
}
