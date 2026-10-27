import SwiftUI
import WatchConnectivity
import WatchKit
import WatchDocsKit

@main
struct WatchDocsWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                LibraryView()
            }
            .environment(WatchLibrary.shared)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                WatchLibrary.shared.reload()
                let receiver = WatchLibrary.shared.receiver
                Task.detached(priority: .utility) {
                    receiver.requestMissingFiles()
                    await receiver.assembler.cleanStaging()
                }
            }
        }
    }
}

/// Activates WatchConnectivity at launch (also when launched in background)
/// and keeps background refresh tasks alive until pending content is received (WCH-01).
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    private var pendingTasks: [WKWatchConnectivityRefreshBackgroundTask] = []

    func applicationDidFinishLaunching() {
        MainActor.assumeIsolated { _ = WatchLibrary.shared }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        MainActor.assumeIsolated { _ = WatchLibrary.shared }
        for task in backgroundTasks {
            if let connectivityTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                pendingTasks.append(connectivityTask)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
        completeWhenIdle()
    }

    private func completeWhenIdle() {
        guard !pendingTasks.isEmpty else { return }
        Task { @MainActor in
            // Wait until WatchConnectivity has delivered everything (max ~25 s).
            for _ in 0..<50 where WCSession.default.hasContentPending {
                try? await Task.sleep(for: .milliseconds(500))
            }
            // Let the receiver finish moving and verifying files.
            try? await Task.sleep(for: .seconds(1))
            for task in self.pendingTasks {
                task.setTaskCompletedWithSnapshot(false)
            }
            self.pendingTasks.removeAll()
        }
    }
}
