import ActivityKit
import Foundation
import OSLog

actor ScheduledTransactionLiveActivityService {
    static let shared = ScheduledTransactionLiveActivityService()

    private let maximumDuration: TimeInterval = 8 * 60 * 60
    private let processingGracePeriod: TimeInterval = 30 * 60
    private let logger = Logger(
        subsystem: "com.josephlteif.financedemo",
        category: "ScheduledLiveActivity"
    )

    func refresh(schedules: [ScheduledTransaction], isEnabled: Bool) async {
        let now = Date.now
        let existingActivities = Activity<ScheduledTransactionActivityAttributes>.activities

        guard isEnabled else {
            await end(existingActivities)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.error("Scheduled transaction Live Activities are disabled in iOS Settings.")
            await end(existingActivities)
            return
        }
        guard let schedule = schedules
            .filter({ $0.isEnabled && $0.nextRunDate > now })
            .min(by: { $0.nextRunDate < $1.nextRunDate }) else {
            await end(existingActivities)
            return
        }

        let activityStartDate = max(
            now.addingTimeInterval(1),
            schedule.nextRunDate.addingTimeInterval(-maximumDuration)
        )
        let groupedSchedules = schedules
            .filter {
                $0.isEnabled
                    && $0.nextRunDate >= schedule.nextRunDate
                    && $0.nextRunDate <= schedule.nextRunDate.addingTimeInterval(maximumDuration)
            }
            .sorted { $0.nextRunDate < $1.nextRunDate }
        let items = groupedSchedules.prefix(3).map {
            ScheduledTransactionActivityItem(id: $0.id, dueDate: $0.nextRunDate)
        }
        let state = ScheduledTransactionActivityAttributes.ContentState(
            items: items,
            additionalItemsCount: groupedSchedules.count - items.count
        )
        let attributes = ScheduledTransactionActivityAttributes(
            primaryScheduleID: schedule.id,
            primaryDueDate: schedule.nextRunDate,
            startDate: activityStartDate
        )
        let content = ActivityContent(
            state: state,
            staleDate: groupedSchedules.last?.nextRunDate.addingTimeInterval(processingGracePeriod)
        )

        if let matchingActivity = existingActivities.first(where: {
            $0.attributes.primaryScheduleID == attributes.primaryScheduleID
                && $0.attributes.primaryDueDate == attributes.primaryDueDate
                && $0.activityState != .ended
                && $0.activityState != .dismissed
                && ($0.attributes.startDate == attributes.startDate
                    || $0.activityState == .active
                    || $0.activityState == .stale)
        }) {
            if matchingActivity.content.state != content.state {
                await matchingActivity.update(content)
            }
            await end(existingActivities.filter { $0.id != matchingActivity.id })
            return
        }

        await end(existingActivities)
        let alert = AlertConfiguration(
            title: state.totalItemsCount == 1 ? "Scheduled transaction" : "Scheduled transactions",
            body: "A private countdown to your scheduled entries is now available.",
            sound: .default
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil,
                style: .standard,
                alertConfiguration: alert,
                start: activityStartDate
            )
            let activityState = String(describing: activity.activityState)
            logger.info("Scheduled transaction Live Activity accepted with state \(activityState, privacy: .public).")
        } catch {
            let errorDescription = error.localizedDescription
            logger.error("Could not schedule transaction Live Activity: \(errorDescription, privacy: .public)")
        }
    }

    private func end(
        _ activities: [Activity<ScheduledTransactionActivityAttributes>]
    ) async {
        for activity in activities {
            nonisolated(unsafe) let activityHandle = activity
            await activityHandle.end(nil, dismissalPolicy: .immediate)
        }
    }
}
