import XCTest

/// Records a voice note with `-UITestSyntheticAudioLevels` and checks the live waveform from
/// screenshots: bars scroll in from the right, a steady level draws equal bars, and the level
/// decays back to the flat dotted line after the synthetic sound stops.
///
/// The synthetic seam emits level 0.6 at 20 Hz for 2 seconds from the moment recording starts,
/// then 0 (see `AudioRecorderWrapper.startSyntheticLevelsIfNeeded`). Recording itself still uses
/// `AVAudioRecorder`, so the microphone must be allowed. The test runs one warm-up recording
/// first to clear any permission alert (microphone, speech recognition), then records again for
/// the timed screenshots.
///
/// The waveform is a SwiftUI `Canvas`, which has no accessibility elements, so the bars are
/// measured from screenshot pixels inside the waveform card. The card's frame comes from the
/// layout in `VoiceAudioView`: 12 pt below the navigation bar, 16 pt screen inset, 8 pt/16 pt card
/// padding, 110 pt tall.
///
/// Every state saves a screenshot (kept even on success) for the UI check on the issue.
@MainActor
final class VoiceRecorderWaveformUITests: XCTestCase {
    private let seededLearningID = "00000000-0000-0000-0000-000000000001"
    private let timeout: TimeInterval = 10
    /// Screen width and the waveform drawing area, in points. Read once per recorder sheet: XCUI
    /// frame queries cost ~0.2 s each, too slow to repeat between timed screenshots.
    private var screenWidth: CGFloat = 0
    private var cardTop: CGFloat = 0

    /// `ReflectWaveform.Style.full`: 3 pt bars on a 5 pt slot.
    private let barWidth: CGFloat = 3
    private let slotWidth: CGFloat = 5
    /// `LiveWaveformBuffer.emissionInterval`: one level every 50 ms.
    private let emissionInterval: TimeInterval = 0.05
    /// A bar at or below this height is the resting dot (`barWidth`), with antialiasing slack.
    private let restingMaxHeight: CGFloat = 5
    /// A bar at or above this height is drawn from the synthetic 0.6 level.
    private let loudMinHeight: CGFloat = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLiveWaveformScrollsSteadyAndDecaysWithSyntheticLevels() throws {
        let app = launch()
        openVoiceRecorder(in: app)
        warmUpRecording(in: app)
        openVoiceRecorder(in: app)
        let navBar = app.navigationBars["Voice Note"]
        XCTAssertTrue(navBar.exists, "No Voice Note navigation bar")
        screenWidth = app.frame.width
        cardTop = navBar.frame.maxY + 12

        // Idle: nothing recorded yet, every bar is the resting dot.
        let idle = try waveform(in: app)
        attachScreenshot("1-idle", idle.screenshot)
        XCTAssertFalse(idle.bars.isEmpty, "No waveform bars found in the idle card")
        XCTAssertTrue(
            idle.bars.allSatisfy { $0.height <= restingMaxHeight },
            "Idle waveform is not flat: \(idle.heightsDescription)"
        )

        let tap = Date()
        recordButton(in: app).tap()

        // Rising: the first loud bars enter from the right edge. Recording (and so the synthetic
        // clock) starts a few hundred ms after the tap, so the later screenshots are timed from
        // the synthetic start, estimated from how many loud bars rising already shows.
        let rising = try firstLoudWaveform(in: app, since: tap)
        attachScreenshot("2-rising-\(rising.label)", rising.screenshot)
        let risingLoudCount = rising.bars.filter { $0.height >= loudMinHeight }.count
        let start = tap.addingTimeInterval(rising.elapsed - Double(risingLoudCount) * emissionInterval)

        // Steady: the constant level has converged into a run of equal bars ending at the right.
        let steady = try waveform(in: app, at: 1.5, since: start)
        attachScreenshot("3-steady-\(steady.label)", steady.screenshot)

        // Decaying: the synthetic level dropped to 0 at 2 s, the newest bars step down.
        let decaying = try waveform(in: app, at: 2.45, since: start)
        attachScreenshot("4-decaying-\(decaying.label)", decaying.screenshot)

        // Silent: ~2 s after the level dropped, the right side is back to the resting dots (the
        // release takes ~18 levels to reach them) and the loud run has scrolled left.
        // A burst while the loud run scrolls away, to check the bar grid itself moves. Frames are
        // 0.27 s apart, not a multiple of the 50 ms emission interval, so each lands at a different
        // point of the scroll between two levels.
        let silentBurst = try (0..<4).map { try waveform(in: app, at: 3.3 + Double($0) * 0.27, since: start) }
        let silent = silentBurst[silentBurst.count - 1]
        attachScreenshot("5-silent-\(silent.label)", silent.screenshot)

        assertOnSlotGrid(steady, "steady")

        // The bars move with the content. A renderer with a fixed stripe grid (the bug this card
        // fixes) draws every bar at the same x phase in every screenshot; a scrolling grid does not.
        let phases = silentBurst.map(gridPhase)
        let phaseSpread = (phases.max() ?? 0) - (phases.min() ?? 0)
        XCTAssertGreaterThan(phaseSpread, 0.5, "The bar grid does not scroll, x phases: \(phases)")
        assertOnSlotGrid(silent, "silent")

        // Rising has fewer loud bars than steady: bars scroll in, they don't appear all at once.
        let risingLoud = rising.bars.filter { $0.height >= loudMinHeight }
        let steadyLoud = steady.bars.filter { $0.height >= loudMinHeight }
        XCTAssertFalse(risingLoud.isEmpty, "No loud bar 0.6 s after recording started: \(rising.heightsDescription)")
        XCTAssertLessThan(risingLoud.count, steadyLoud.count, "The loud run did not grow from rising to steady")
        XCTAssertEqual(risingLoud.last?.index, rising.bars.last?.index, "Rising: the newest bar is not the loud one on the right")

        // Steady: loud run touches the right edge and every bar in it has the same height.
        XCTAssertGreaterThanOrEqual(steadyLoud.count, 20, "Steady: expected a long loud run, got \(steady.heightsDescription)")
        XCTAssertEqual(steadyLoud.last?.index, steady.bars.last?.index, "Steady: the loud run does not end at the right edge")
        assertContiguous(steadyLoud, "steady loud run")
        // Skip the first loud bars: they carry the attack from silence.
        let plateau = steadyLoud.dropFirst(8).map(\.height)
        let plateauSpread = (plateau.max() ?? 0) - (plateau.min() ?? 0)
        XCTAssertLessThanOrEqual(plateauSpread, 2, "Steady level jumps: plateau heights \(plateau.map { Int($0.rounded()) })")
        let plateauHeight = plateau.reduce(0, +) / CGFloat(max(1, plateau.count))

        // Decaying: the newest bar is lower than the plateau, and heights step down to the right.
        let decayTail = decaying.bars.suffix(6).map(\.height)
        XCTAssertLessThan(decayTail.last ?? .infinity, plateauHeight - 4, "Decaying: newest bar did not drop: \(decaying.heightsDescription)")
        XCTAssertTrue(
            zip(decayTail, decayTail.dropFirst()).allSatisfy { $1 <= $0 + 1 },
            "Decaying: bars do not step down toward the right: \(decayTail.map { Int($0.rounded()) })"
        )
        XCTAssertTrue(
            decaying.bars.contains { abs($0.height - plateauHeight) <= 2 },
            "Decaying: the plateau is gone too early: \(decaying.heightsDescription)"
        )
        // Slow release: ~0.45 s after the level dropped, several bars right of the plateau sit
        // between rest and plateau. Left of the plateau are the attack bars, not the release.
        let lastPlateauIndex = decaying.bars.last { abs($0.height - plateauHeight) <= 2 }?.index ?? .max
        let decayingSteps = decaying.bars.filter {
            $0.index > lastPlateauIndex && $0.height > restingMaxHeight && $0.height < plateauHeight - 4
        }
        XCTAssertGreaterThanOrEqual(decayingSteps.count, 3, "Decaying: no gradual release: \(decaying.heightsDescription)")

        // Silent: the last 10 bars are resting dots, and the loud run moved left of where it ended.
        XCTAssertTrue(
            silent.bars.suffix(10).allSatisfy { $0.height <= restingMaxHeight },
            "Silent: right side is not flat: \(silent.heightsDescription)"
        )
        let silentLoud = silent.bars.filter { $0.height >= loudMinHeight }
        XCTAssertFalse(silentLoud.isEmpty, "Silent: the loud run scrolled away too early")
        if let silentEnd = silentLoud.last?.minX, let steadyEnd = steadyLoud.last?.minX {
            XCTAssertLessThan(silentEnd, steadyEnd - 10 * slotWidth, "Silent: the loud run did not scroll left")
        }
    }

    // MARK: - Flow

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-UITestSyntheticAudioLevels",
            "-hasCompletedOnboarding", "YES",
            "-debugAlwaysShowOnboarding", "NO",
            "-lastOpenedLearningId", seededLearningID,
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout))
        XCTAssertTrue(element("reflections.list", in: app).waitForExistence(timeout: timeout))
        // A failed assertion stops the test mid-recording, and a recording app stalls the
        // test run's shutdown for minutes. Cancel whatever is still open.
        addTeardownBlock { @MainActor in
            let cancel = app.navigationBars["Voice Note"].buttons["Cancel"]
            if cancel.exists { cancel.tap() }
        }
        return app
    }

    private func openVoiceRecorder(in app: XCUIApplication) {
        app.open(URL(string: "reflect://voice")!)
        XCTAssertTrue(element("voice.recorder", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(recordButton(in: app).waitForExistence(timeout: timeout), "No record button")
    }

    /// Records once and cancels, answering any permission alert on the way, so the timed run
    /// starts with no alert over the waveform.
    private func warmUpRecording(in app: XCUIApplication) {
        recordButton(in: app).tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            let alert = springboard.alerts.firstMatch
            if alert.waitForExistence(timeout: 1) {
                let allow = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "OK"])).firstMatch
                if allow.exists { allow.tap() }
            } else if !recordButton(in: app).exists {
                break
            }
        }
        XCTAssertTrue(
            recordButton(in: app).waitForNonExistence(timeout: timeout),
            "Recording did not start. Is the microphone allowed on this simulator?"
        )
        app.navigationBars["Voice Note"].buttons["Cancel"].tap()
        XCTAssertTrue(element("voice.recorder", in: app).waitForNonExistence(timeout: timeout))
    }

    private func recordButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'voice.record' AND label == 'Start recording'")).firstMatch
    }

    // MARK: - Waveform measurement

    private struct Bar {
        let index: Int
        /// Left edge in points, from the card's left edge.
        let minX: CGFloat
        let height: CGFloat
    }

    private struct Measurement {
        let screenshot: XCUIScreenshot
        let bars: [Bar]
        let elapsed: TimeInterval

        var label: String { "t\(Int((elapsed * 1000).rounded()))ms" }
        var heightsDescription: String { bars.map { String(Int($0.height.rounded())) }.joined(separator: " ") }
    }

    /// Waits until `delay` seconds after `start`, then screenshots and measures the waveform.
    private func waveform(in app: XCUIApplication, at delay: TimeInterval = 0, since start: Date = Date()) throws -> Measurement {
        let wait = delay - Date().timeIntervalSince(start)
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        // The screenshot call takes 0.1 to 0.3 s. Stamp its midpoint as the moment captured.
        let before = Date().timeIntervalSince(start)
        let screenshot = app.screenshot()
        let elapsed = (before + Date().timeIntervalSince(start)) / 2
        let bars = try measureBars(in: screenshot)
        return Measurement(screenshot: screenshot, bars: bars, elapsed: elapsed)
    }

    /// Screenshots every pass until a loud bar shows up, at most 3 s after `start`.
    private func firstLoudWaveform(in app: XCUIApplication, since start: Date) throws -> Measurement {
        while true {
            let measurement = try waveform(in: app, since: start)
            if measurement.bars.contains(where: { $0.height >= loudMinHeight }) || measurement.elapsed > 3 {
                return measurement
            }
        }
    }

    /// Finds the bars inside the waveform card: columns whose pixels differ from the card
    /// background, grouped into runs, each run measured for its tallest column.
    private func measureBars(in screenshot: XCUIScreenshot) throws -> [Bar] {
        // Drawing area inside the card: 16 pt screen inset + 8 pt card padding, 16 pt top padding.
        let area = CGRect(x: 24, y: cardTop + 16, width: screenWidth - 48, height: 110)

        let image = try XCTUnwrap(screenshot.image.cgImage, "Screenshot has no CGImage")
        let pixels = try PixelReader(image)
        let scale = CGFloat(image.width) / screenWidth

        let px = { (value: CGFloat) in Int((value * scale).rounded()) }
        let left = px(area.minX), right = px(area.maxX), top = px(area.minY), bottom = px(area.maxY)
        // Card background: the top padding strip, above the drawing area.
        let background = pixels.color(x: left + px(4), y: px(cardTop + 6))

        var columnHeights: [Int] = []
        for x in left..<right {
            var minY = Int.max, maxY = Int.min
            for y in top..<bottom where pixels.color(x: x, y: y).distance(to: background) > 60 {
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
            columnHeights.append(minY <= maxY ? maxY - minY + 1 : 0)
        }

        var bars: [Bar] = []
        var runStart: Int?
        for (offset, height) in (columnHeights + [0]).enumerated() {
            if height > 0, runStart == nil { runStart = offset }
            if height == 0, let start = runStart {
                let tallest = columnHeights[start..<offset].max() ?? 0
                bars.append(Bar(index: bars.count, minX: CGFloat(start) / scale, height: CGFloat(tallest) / scale))
                runStart = nil
            }
        }
        // A bar clipped by the card's edge mid-scroll is partial. Drop edge fragments so the
        // grid checks see whole bars only.
        return bars.filter { bar in
            bar.minX > 0.5 && bar.minX + barWidth < area.width - 0.5
        }.enumerated().map { Bar(index: $0.offset, minX: $0.element.minX, height: $0.element.height) }
    }

    /// Where the bars sit on the slot grid, 0 ..< `slotWidth` pt, as the median over all bars.
    private func gridPhase(_ measurement: Measurement) -> CGFloat {
        let phases = measurement.bars.map { $0.minX.truncatingRemainder(dividingBy: slotWidth) }.sorted()
        return phases.isEmpty ? 0 : phases[phases.count / 2]
    }

    /// Consecutive bars sit one slot apart, never merged or skipped.
    private func assertOnSlotGrid(_ measurement: Measurement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let gaps = zip(measurement.bars, measurement.bars.dropFirst()).map { $1.minX - $0.minX }
        XCTAssertGreaterThan(gaps.count, 40, "\(name): too few bars measured", file: file, line: line)
        let offGrid = gaps.filter { abs($0 - slotWidth) > 1 }
        XCTAssertTrue(offGrid.isEmpty, "\(name): bars off the \(slotWidth) pt slot grid: \(offGrid)", file: file, line: line)
    }

    private func assertContiguous(_ bars: [Bar], _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let indices = bars.map(\.index)
        XCTAssertEqual(indices, Array((indices.first ?? 0)...(indices.last ?? -1)), "\(name) has gaps", file: file, line: line)
    }

    // MARK: - Helpers

    private func attachScreenshot(_ name: String, _ screenshot: XCUIScreenshot) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

private struct PixelReadError: Error {}

/// RGBA pixel access for a screenshot, redrawn into a known 8-bit RGBA layout.
private struct PixelReader {
    struct RGB {
        let r: Int, g: Int, b: Int

        func distance(to other: RGB) -> Int {
            abs(r - other.r) + abs(g - other.g) + abs(b - other.b)
        }
    }

    private let data: [UInt8]
    private let width: Int

    init(_ image: CGImage) throws {
        width = image.width
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw PixelReadError() }
        data = buffer
    }

    func color(x: Int, y: Int) -> RGB {
        let offset = (y * width + x) * 4
        return RGB(r: Int(data[offset]), g: Int(data[offset + 1]), b: Int(data[offset + 2]))
    }
}
