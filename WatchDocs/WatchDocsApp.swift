import BackgroundTasks
import SwiftData
import SwiftUI
import UserNotifications
import WatchDocsKit

@main
struct WatchDocsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppServices.shared.pipeline)
                .environment(AppServices.shared.settings)
                .modelContainer(AppServices.shared.container)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                AppServices.shared.pipeline.processInbox()
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            case .background:
                BackgroundInbox.scheduleIfNeeded()
            default:
                break
            }
        }
    }
}

/// Long-lived services. Created at launch so WCSession is activated early,
/// including when iOS wakes the app in the background.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let container: ModelContainer
    let settings: AppSettings
    let transport: PhoneTransport
    let pipeline: DocumentPipeline

    private init() {
        do {
            container = try ModelContainer(for: SentDocument.self)
        } catch {
            fatalError("Could not open the document database: \(error)")
        }
        settings = AppSettings()
        StoragePaths.prepare()
        let link = WatchConnectivityLink(stagingDirectory: StoragePaths.staging)
        transport = PhoneTransport(link: link)
        pipeline = DocumentPipeline(settings: settings, transport: transport, context: container.mainContext)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundInbox.register()
        UNUserNotificationCenter.current().delegate = self
        // Touch the services so WatchConnectivity is activated right away.
        MainActor.assumeIsolated { _ = AppServices.shared }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { AppServices.shared.pipeline.processInbox() }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}

/// SHR-03: converts and sends shared files when iOS grants background time.
enum BackgroundInbox {
    static var identifier: String { (Bundle.main.bundleIdentifier ?? "com.example.watchdocs") + ".inbox" }

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            let work = Task { @MainActor in
                let pipeline = AppServices.shared.pipeline
                pipeline.processInbox()
                while pipeline.isConverting && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                // Give WatchConnectivity a moment to pick up the queued files.
                try? await Task.sleep(for: .seconds(2))
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func scheduleIfNeeded() {
        guard !SharedInbox.isEmpty else { return }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }
}
