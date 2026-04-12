import XCTest
@testable import JustNow

@MainActor
final class CaptureEventControllerTests: XCTestCase {
    func testHandleSessionResignActiveCancelsPendingStartAndSchedulesStop() {
        let recorder = CaptureEventControllerRecorder(
            context: CaptureEventContext(
                hasCaptureManager: true,
                isCapturing: true,
                isSetupCaptureInProgress: false,
                hasPendingStart: true,
                isOverlayVisible: false
            )
        )
        let controller = recorder.makeController()

        controller.handleSessionResignActive()

        XCTAssertEqual(
            recorder.events,
            [
                "cancelPendingStart",
                "stop:Session Inactive"
            ]
        )
    }

    func testHandleSessionBecomeActiveSchedulesResumeAfterPriorPause() {
        let recorder = CaptureEventControllerRecorder(
            context: CaptureEventContext(
                hasCaptureManager: true,
                isCapturing: true,
                isSetupCaptureInProgress: false,
                hasPendingStart: false,
                isOverlayVisible: false
            )
        )
        let controller = recorder.makeController()

        controller.handleSessionResignActive()
        recorder.clearEvents()
        recorder.context = CaptureEventContext(
            hasCaptureManager: true,
            isCapturing: false,
            isSetupCaptureInProgress: false,
            hasPendingStart: false,
            isOverlayVisible: false
        )

        controller.handleSessionBecomeActive()

        XCTAssertEqual(recorder.events, ["filter:5", "start:Resuming..."])
        XCTAssertEqual(recorder.startRequests.count, 1)
        XCTAssertEqual(recorder.startRequests[0].attempt.successMessage, "Capture resumed after session active")
        XCTAssertEqual(recorder.startRequests[0].retry?.delay, .seconds(3))
    }

    func testToggleCapturePauseWithoutCaptureManagerUpdatesPauseMenuAndStatus() {
        let recorder = CaptureEventControllerRecorder(
            context: CaptureEventContext(
                hasCaptureManager: false,
                isCapturing: false,
                isSetupCaptureInProgress: false,
                hasPendingStart: false,
                isOverlayVisible: false
            )
        )
        let controller = recorder.makeController()

        controller.toggleCapturePause()
        controller.toggleCapturePause()

        XCTAssertEqual(
            recorder.events,
            [
                "pauseMenu:true",
                "status:Paused (User)",
                "pauseMenu:false",
                "status:Starting..."
            ]
        )
    }

    func testHandleUnexpectedStopRestartsAndEndsForegroundActivity() {
        let recorder = CaptureEventControllerRecorder(
            context: CaptureEventContext(
                hasCaptureManager: true,
                isCapturing: false,
                isSetupCaptureInProgress: false,
                hasPendingStart: false,
                isOverlayVisible: false
            )
        )
        let controller = recorder.makeController()

        controller.handleUnexpectedStop()

        XCTAssertEqual(
            recorder.events,
            [
                "log:Capture stopped unexpectedly, attempting restart...",
                "endForegroundActivity",
                "start:Restarting..."
            ]
        )
        XCTAssertEqual(recorder.startRequests[0].attempt.successMessage, "Capture restarted successfully")
    }
}

@MainActor
private final class CaptureEventControllerRecorder {
    var context: CaptureEventContext
    private(set) var events: [String] = []
    private(set) var startRequests: [CaptureStartRequest] = []

    init(context: CaptureEventContext) {
        self.context = context
    }

    func clearEvents() {
        events.removeAll()
    }

    func makeController() -> CaptureEventController {
        CaptureEventController(
            context: { [unowned self] in self.context },
            scheduleStart: { [unowned self] request in
                self.events.append("start:\(request.status)")
                self.startRequests.append(request)
            },
            cancelPendingStart: { [unowned self] in
                self.events.append("cancelPendingStart")
            },
            scheduleStop: { [unowned self] request in
                self.events.append("stop:\(request.status)")
            },
            updateStatus: { [unowned self] status in
                self.events.append("status:\(status)")
            },
            enableBlackFrameFilter: { [unowned self] frameCount in
                self.events.append("filter:\(frameCount)")
            },
            endForegroundActivity: { [unowned self] in
                self.events.append("endForegroundActivity")
            },
            updatePauseMenu: { [unowned self] isPaused in
                self.events.append("pauseMenu:\(isPaused)")
            },
            logger: { [unowned self] message in
                self.events.append("log:\(message)")
            }
        )
    }
}
