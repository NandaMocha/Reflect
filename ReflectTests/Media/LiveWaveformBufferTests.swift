import Testing
import CoreGraphics
@testable import Reflect

/// The live recording waveform must scroll exactly one bar per level update, lift quiet speech,
/// and rise fast / fall slowly. Samples use DSWaveformImage's convention: `0` = loud, `1` = silent.
struct LiveWaveformBufferTests {
    private let tolerance: Float = 0.0001

    /// Loudness (`1` = loud) of the newest bar, i.e. the inverse of the stored sample.
    private func newestLoudness(_ buffer: LiveWaveformBuffer) -> Float {
        1 - (buffer.samples.last ?? 1)
    }

    // MARK: - Bar count

    @Test(arguments: [
        (CGFloat(300), ReflectWaveform.Style.full, 60),
        (CGFloat(302), ReflectWaveform.Style.full, 60),
        (CGFloat(303), ReflectWaveform.Style.full, 61),
        (CGFloat(343), ReflectWaveform.Style.full, 69),
        (CGFloat(300), ReflectWaveform.Style.compact, 100),
        (CGFloat(301), ReflectWaveform.Style.compact, 100),
        (CGFloat(302), ReflectWaveform.Style.compact, 101),
        (CGFloat(300), ReflectWaveform.Style.minimal, 150),
        (CGFloat(301), ReflectWaveform.Style.minimal, 150)
    ])
    func barCountFillsTheWidth(width: CGFloat, style: ReflectWaveform.Style, expected: Int) {
        let count = LiveWaveformBuffer.barCount(
            width: width,
            barWidth: style.barWidth,
            barSpacing: style.barSpacing
        )
        #expect(count == expected)
    }

    @Test(arguments: [CGFloat(0), CGFloat(1), CGFloat(-20)])
    func barCountIsAtLeastOne(width: CGFloat) {
        #expect(LiveWaveformBuffer.barCount(width: width, barWidth: 3, barSpacing: 2) == 1)
    }

    // MARK: - Rolling window

    @Test func startsFullOfSilence() {
        let buffer = LiveWaveformBuffer(count: 12)
        #expect(buffer.samples == [Float](repeating: 1, count: 12))
    }

    @Test func appendShiftsEveryBarExactlyOneSlot() {
        var buffer = LiveWaveformBuffer(count: 20)
        let levels: [Float] = [0.2, 0.9, 0.5, 0.0, 0.7, 1.0, 0.3, 0.05, 0.6, 0.4]

        for level in levels {
            let before = buffer.samples
            buffer.append(level: level)
            let after = buffer.samples

            #expect(after.count == before.count)
            for index in 0..<(after.count - 1) {
                #expect(after[index] == before[index + 1])
            }
        }
    }

    @Test func newestValueLandsOnTheRight() {
        var buffer = LiveWaveformBuffer(count: 8)
        buffer.append(level: 1)
        #expect(buffer.samples.dropLast().allSatisfy { $0 == 1 })
        #expect(newestLoudness(buffer) > 0)
    }

    @Test func samplesStayInRange() {
        var buffer = LiveWaveformBuffer(count: 10)
        for level in [Float(-1), 0, 0.5, 1, 2, .nan, .infinity] {
            buffer.append(level: level)
        }
        #expect(buffer.samples.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test func resetReturnsToSilence() {
        var buffer = LiveWaveformBuffer(count: 6)
        for _ in 0..<6 { buffer.append(level: 1) }
        buffer.reset()
        #expect(buffer.samples == [Float](repeating: 1, count: 6))

        // The envelope restarts too: a first quiet tick must not inherit the old loudness.
        buffer.append(level: 0)
        #expect(newestLoudness(buffer) == 0)
    }

    // MARK: - Resize

    @Test func resizeLargerKeepsNewestValuesOnTheRight() {
        var buffer = LiveWaveformBuffer(count: 4)
        for level in [Float(0.3), 0.6, 0.9, 1.0] { buffer.append(level: level) }
        let before = buffer.samples

        buffer.resize(to: 7)

        #expect(buffer.samples.count == 7)
        #expect(Array(buffer.samples.suffix(4)) == before)
        #expect(buffer.samples.prefix(3).allSatisfy { $0 == 1 })
    }

    @Test func resizeSmallerKeepsNewestValues() {
        var buffer = LiveWaveformBuffer(count: 6)
        for level in [Float(0.2), 0.4, 0.6, 0.8, 1.0, 0.5] { buffer.append(level: level) }
        let before = buffer.samples

        buffer.resize(to: 3)

        #expect(buffer.samples == Array(before.suffix(3)))
    }

    @Test func resizeToSameCountChangesNothing() {
        var buffer = LiveWaveformBuffer(count: 5)
        buffer.append(level: 0.7)
        let before = buffer.samples
        buffer.resize(to: 5)
        #expect(buffer.samples == before)
    }

    @Test func resizeNeverGoesBelowOneBar() {
        var buffer = LiveWaveformBuffer(count: 5)
        buffer.resize(to: 0)
        #expect(buffer.samples.count == 1)
    }

    // MARK: - Curve

    @Test func curveMapsEndpoints() {
        #expect(LiveWaveformBuffer.curve(0) == 0)
        #expect(abs(LiveWaveformBuffer.curve(1) - 1) < tolerance)
    }

    @Test func curveIsMonotonicAndBounded() {
        var previous: Float = 0
        for step in 0...100 {
            let value = LiveWaveformBuffer.curve(Float(step) / 100)
            #expect(value >= previous)
            #expect(value >= 0 && value <= 1)
            previous = value
        }
    }

    @Test func curveGatesNoiseToSilence() {
        let gate = LiveWaveformBuffer.Tuning.standard.noiseGate
        #expect(gate > 0)
        #expect(LiveWaveformBuffer.curve(gate * 0.5) == 0)
        #expect(LiveWaveformBuffer.curve(gate * 0.99) == 0)
    }

    @Test func curveLiftsQuietSpeech() {
        #expect(LiveWaveformBuffer.curve(0.3) >= 0.35)
    }

    @Test func silenceStaysAFlatLine() {
        var buffer = LiveWaveformBuffer(count: 10)
        let belowGate = LiveWaveformBuffer.Tuning.standard.noiseGate * 0.5
        for _ in 0..<30 { buffer.append(level: belowGate) }
        #expect(buffer.samples.allSatisfy { $0 == 1 })
    }

    // MARK: - Envelope

    @Test func constantInputConvergesAndHoldsSteady() {
        var buffer = LiveWaveformBuffer(count: 80)
        var loudness: [Float] = []
        for _ in 0..<60 {
            buffer.append(level: 0.6)
            loudness.append(newestLoudness(buffer))
        }

        let target = LiveWaveformBuffer.curve(0.6)
        #expect(abs(loudness[59] - target) < 0.01)
        for tick in 20..<60 {
            #expect(abs(loudness[tick] - loudness[tick - 1]) < 0.01)
        }
    }

    @Test func attackReachesMostOfAJumpInOneTick() {
        var buffer = LiveWaveformBuffer(count: 10)
        buffer.append(level: 1)
        #expect(newestLoudness(buffer) >= 0.6 - tolerance)
    }

    @Test func releaseDecaysSlowly() {
        var buffer = LiveWaveformBuffer(count: 10)
        for _ in 0..<40 { buffer.append(level: 1) }
        #expect(newestLoudness(buffer) > 0.99)

        var ticksUntilQuiet = 0
        while newestLoudness(buffer) >= 0.2 {
            buffer.append(level: 0)
            ticksUntilQuiet += 1
            if ticksUntilQuiet > 200 { break }
        }

        #expect(ticksUntilQuiet >= 4)
        #expect(ticksUntilQuiet <= 40)
    }

    @Test func releaseEventuallyReachesExactSilence() {
        var buffer = LiveWaveformBuffer(count: 10)
        for _ in 0..<40 { buffer.append(level: 1) }
        for _ in 0..<200 { buffer.append(level: 0) }
        #expect(buffer.samples.last == 1)
    }

    // MARK: - Scroll offset

    @Test func scrollOffsetIsZeroRightAfterAppend() {
        #expect(LiveWaveformBuffer.scrollOffset(elapsed: 0, slotWidth: 5) == 0)
    }

    @Test func scrollOffsetIsHalfwayAtHalfTheInterval() {
        let offset = LiveWaveformBuffer.scrollOffset(elapsed: 0.025, slotWidth: 5, interval: 0.05)
        #expect(abs(offset - 2.5) < 0.0001)
    }

    @Test(arguments: [0.05, 0.051, 0.2, 10, Double.infinity])
    func scrollOffsetStopsAtOneSlot(elapsed: Double) {
        #expect(LiveWaveformBuffer.scrollOffset(elapsed: elapsed, slotWidth: 5, interval: 0.05) == 5)
    }

    @Test func scrollOffsetNeverLeavesTheSlot() {
        for step in -20...200 {
            let offset = LiveWaveformBuffer.scrollOffset(
                elapsed: Double(step) / 1000,
                slotWidth: 5,
                interval: 0.05
            )
            #expect(offset >= 0 && offset <= 5)
        }
    }

    // MARK: - Bar layout

    @Test func barsSitOnTheSlotGridAndHandOverWithoutAJump() {
        let slot: CGFloat = 5
        let visible = 60
        let count = visible + 1

        // Right after an append the newest bar waits one slot past the right edge.
        let newest = LiveWaveformBuffer.barOriginX(
            index: count - 1, count: count, visibleBars: visible, slotWidth: slot, scrollOffset: 0
        )
        #expect(newest == CGFloat(visible) * slot)

        // A bar that finished scrolling sits exactly where the next append will draw it.
        for index in 1..<count {
            let endOfScroll = LiveWaveformBuffer.barOriginX(
                index: index, count: count, visibleBars: visible, slotWidth: slot, scrollOffset: slot
            )
            let afterAppend = LiveWaveformBuffer.barOriginX(
                index: index - 1, count: count, visibleBars: visible, slotWidth: slot, scrollOffset: 0
            )
            #expect(endOfScroll == afterAppend)
            #expect(afterAppend.truncatingRemainder(dividingBy: slot) == 0)
        }
    }

    @Test func barHeightKeepsADotForSilenceAndScalesLoudness() {
        #expect(LiveWaveformBuffer.barHeight(sample: 1, canvasHeight: 100, minimum: 3) == 3)
        #expect(LiveWaveformBuffer.barHeight(sample: 0, canvasHeight: 100, minimum: 3) == 95)
        #expect(LiveWaveformBuffer.barHeight(sample: 0.5, canvasHeight: 100, minimum: 3) == 47.5)
    }
}
