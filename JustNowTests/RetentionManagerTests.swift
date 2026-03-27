import XCTest
@testable import JustNow

@MainActor
final class RetentionManagerTests: XCTestCase {

    // MARK: - Helpers

    private func makeFrame(id: UUID = UUID(), secondsAgo: TimeInterval, hash: UInt64 = 1, relativeTo now: Date = Date()) -> StoredFrame {
        StoredFrame(id: id, timestamp: now.addingTimeInterval(-secondsAgo), hash: hash)
    }

    private func makeFrames(count: Int, spacingSeconds: TimeInterval, startingSecondsAgo: TimeInterval, relativeTo now: Date) -> [StoredFrame] {
        (0..<count).map { i in
            let age = startingSecondsAgo - Double(i) * spacingSeconds
            return makeFrame(secondsAgo: age, relativeTo: now)
        }
        // Sort oldest-first to match FrameBuffer ordering
        .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Basic behaviour

    func testEmptyFrameListReturnsNoPrunes() {
        let manager = RetentionManager(policy: .default24Hours)
        let result = manager.framesToPrune(frames: [], currentTime: Date())
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleFrameIsNeverPruned() {
        let now = Date()
        let frame = makeFrame(secondsAgo: 10, relativeTo: now)
        let manager = RetentionManager(policy: .default24Hours)

        let pruned = manager.framesToPrune(frames: [frame], currentTime: now)
        XCTAssertTrue(pruned.isEmpty, "A single frame should always be kept")
    }

    func testFramesOlderThanMaximumAgeArePruned() {
        let now = Date()
        let policy = RetentionPolicy.rewindHistory(.thirtyMinutes)
        let manager = RetentionManager(policy: policy)

        // retainedDuration for .thirtyMinutes is max(1800, 3600) = 3600
        let old = makeFrame(secondsAgo: policy.maximumAge + 60, relativeTo: now)
        let recent = makeFrame(secondsAgo: 10, relativeTo: now)
        let frames = [old, recent].sorted { $0.timestamp < $1.timestamp }

        let pruned = manager.framesToPrune(frames: frames, currentTime: now)
        XCTAssertTrue(pruned.contains(old.id), "Frame older than maximumAge should be pruned")
        XCTAssertFalse(pruned.contains(recent.id), "Recent frame should be kept")
    }

    // MARK: - Tier spacing enforcement

    func testFirstTierRespectsMinimumSpacing() {
        let now = Date()
        // 24-hour policy: first tier is 0–5 min with 0.5s spacing
        let manager = RetentionManager(policy: .default24Hours)

        // Two frames 0.3s apart within first tier (both < 5 min old)
        let frame1 = makeFrame(secondsAgo: 60, relativeTo: now)
        let frame2 = makeFrame(secondsAgo: 59.7, relativeTo: now)
        let frames = [frame1, frame2].sorted { $0.timestamp < $1.timestamp }

        let pruned = manager.framesToPrune(frames: frames, currentTime: now)
        // frame1 is kept (first in tier), frame2 should be pruned (too close)
        XCTAssertFalse(pruned.contains(frame1.id))
        XCTAssertTrue(pruned.contains(frame2.id), "Frame within 0.5s of previous should be pruned in first tier")
    }

    func testFirstTierKeepsFramesBeyondMinimumSpacing() {
        let now = Date()
        let manager = RetentionManager(policy: .default24Hours)

        // Two frames 1s apart within first tier — both should be kept
        let frame1 = makeFrame(secondsAgo: 60, relativeTo: now)
        let frame2 = makeFrame(secondsAgo: 59, relativeTo: now)
        let frames = [frame1, frame2].sorted { $0.timestamp < $1.timestamp }

        let pruned = manager.framesToPrune(frames: frames, currentTime: now)
        XCTAssertTrue(pruned.isEmpty, "Frames spaced >= 0.5s in first tier should both be kept")
    }

    func testSecondTierEnforcesLargerSpacing() {
        let now = Date()
        // 24-hour policy: second tier is 5–15 min, minimumSpacing = 5s
        let manager = RetentionManager(policy: .default24Hours)

        // Three frames in the 5–15 min range, 3s apart
        let frame1 = makeFrame(secondsAgo: 10 * 60, relativeTo: now)
        let frame2 = makeFrame(secondsAgo: 10 * 60 - 3, relativeTo: now)
        let frame3 = makeFrame(secondsAgo: 10 * 60 - 6, relativeTo: now)
        let frames = [frame1, frame2, frame3].sorted { $0.timestamp < $1.timestamp }

        let pruned = manager.framesToPrune(frames: frames, currentTime: now)
        XCTAssertFalse(pruned.contains(frame1.id), "First frame in tier should be kept")
        XCTAssertTrue(pruned.contains(frame2.id), "Frame only 3s after previous should be pruned (5s spacing required)")
        XCTAssertFalse(pruned.contains(frame3.id), "Frame 6s after first kept frame should be kept")
    }

    // MARK: - Policy switching

    func testUpdatePolicyChangesBehaviour() {
        let now = Date()
        let manager = RetentionManager(policy: .default24Hours)

        // Frame at 25 hours ago — within 24h policy's maximumAge? No, 24h max is 86400.
        // 25 hours = 90000s > 86400s → should be pruned even with 24h policy
        let oldFrame = makeFrame(secondsAgo: 90000, relativeTo: now)
        let recentFrame = makeFrame(secondsAgo: 100, relativeTo: now)
        let frames = [oldFrame, recentFrame].sorted { $0.timestamp < $1.timestamp }

        // With 24h policy, old frame is beyond max age
        let pruned24h = manager.framesToPrune(frames: frames, currentTime: now)
        XCTAssertTrue(pruned24h.contains(oldFrame.id))

        // Switch to 30-min policy — both old and potentially recent frames evaluated differently
        manager.updatePolicy(.rewindHistory(.thirtyMinutes))
        let pruned30m = manager.framesToPrune(frames: frames, currentTime: now)
        XCTAssertTrue(pruned30m.contains(oldFrame.id), "Old frame still beyond max age")
    }

    // MARK: - All four RewindHistoryOption presets

    func testAllRewindHistoryOptionsProduceValidPolicies() {
        for option in RewindHistoryOption.allCases {
            let policy = RetentionPolicy.rewindHistory(option)
            XCTAssertGreaterThan(policy.maximumAge, 0, "\(option) should have positive maximumAge")
            XCTAssertFalse(policy.tiers.isEmpty, "\(option) should have at least one tier")

            // Tiers should be ordered by maxAge
            for i in 1..<policy.tiers.count {
                XCTAssertGreaterThanOrEqual(
                    policy.tiers[i].maxAge,
                    policy.tiers[i - 1].maxAge,
                    "\(option) tiers should have non-decreasing maxAge"
                )
            }

            // Last tier maxAge should cover up to maximumAge
            XCTAssertGreaterThanOrEqual(
                policy.tiers.last!.maxAge,
                policy.maximumAge,
                "\(option) last tier should cover maximumAge"
            )
        }
    }

    func testRetainedDurationIsAtLeastOneHour() {
        for option in RewindHistoryOption.allCases {
            XCTAssertGreaterThanOrEqual(
                option.retainedDuration,
                3600,
                "\(option) retainedDuration should be at least 1 hour"
            )
        }
    }

    // MARK: - Dense frame sequences

    func testDenseFramesInOlderTierAreThinned() {
        let now = Date()
        // 24h policy, third tier: 15 min – 24 hr, minimumSpacing = 30s
        let manager = RetentionManager(policy: .default24Hours)

        // 10 frames at 1-hour mark, 5s apart
        let baseAge: TimeInterval = 3600
        let frames = (0..<10).map { i in
            makeFrame(secondsAgo: baseAge - Double(i) * 5, relativeTo: now)
        }.sorted { $0.timestamp < $1.timestamp }

        let pruned = manager.framesToPrune(frames: frames, currentTime: now)
        let kept = frames.filter { !pruned.contains($0.id) }

        // With 30s spacing, out of 10 frames spanning 45s total, we expect ~2 kept
        XCTAssertLessThan(kept.count, frames.count, "Dense frames in older tier should be thinned")
        XCTAssertGreaterThan(kept.count, 0, "At least one frame should be kept")
    }
}
