import Foundation
import BackgroundTasks
import UIKit
import os

/// Lifecycle + background-task plumbing for auto-sync drains.
///
/// Three complementary triggers keep the outbox moving even when the debounced in-app drain
/// (Task 3) can't run: a foreground/launch flush, a background flush that holds the app alive
/// briefly for an in-flight upload, and a `BGProcessingTask` backstop the OS runs opportunistically.
enum SyncBackgroundScheduler {

    /// Must match the identifier under `BGTaskSchedulerPermittedIdentifiers` in Info.plist
    /// exactly, or `register` throws at launch.
    static let identifier = "xyz.nandamochammad.Reflect.sync-drain"

    // MARK: - BGProcessingTask

    /// Registers the drain handler. Call once, before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { bgTask in
            guard let processingTask = bgTask as? BGProcessingTask else {
                bgTask.setTaskCompleted(success: false)
                return
            }
            handleDrain(processingTask)
        }
    }

    /// Submits the next background drain request. Best-effort — the OS decides when (or whether)
    /// to run it. Throws on the Simulator / unentitled builds, which is harmless: the in-app and
    /// lifecycle flushes still cover those cases.
    static func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("⚠️ Auto-sync BG task submit failed: \(error)")
        }
    }

    private static func handleDrain(_ task: BGProcessingTask) {
        // Chain the next backstop before doing the work, so the schedule survives a crash.
        scheduleProcessingTask()

        // Atomic guard: the work Task (main actor) and the expirationHandler (system queue) can
        // both try to finish the task; setTaskCompleted must be called exactly once.
        let hasCompleted = OSAllocatedUnfairLock(initialState: false)
        func complete(success: Bool) {
            let firstToComplete = hasCompleted.withLock { done -> Bool in
                guard !done else { return false }
                done = true
                return true
            }
            if firstToComplete {
                task.setTaskCompleted(success: success)
            }
        }

        let work = Task { @MainActor in
            await DIContainer.shared.makeSyncCoordinator().drain()
            complete(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            complete(success: false)
        }
    }

    // MARK: - Lifecycle flushes

    /// Foreground / launch flush: drain any ops queued while backgrounded or offline.
    @MainActor
    static func flushForeground() {
        let coordinator = DIContainer.shared.makeSyncCoordinator()
        Task { await coordinator.drain() }
    }

    /// Background flush: request a small extension so an in-flight drain can finish, and submit
    /// the BG backstop for whatever doesn't complete in time.
    @MainActor
    static func flushBackground() {
        scheduleProcessingTask()

        let app = UIApplication.shared
        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        bgTaskID = app.beginBackgroundTask(withName: "auto-sync-drain") {
            if bgTaskID != .invalid {
                app.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }

        let coordinator = DIContainer.shared.makeSyncCoordinator()
        Task { @MainActor in
            await coordinator.drain()
            if bgTaskID != .invalid {
                app.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }
    }
}
