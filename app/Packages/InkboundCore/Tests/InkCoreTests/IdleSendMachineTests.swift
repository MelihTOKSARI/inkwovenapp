import Foundation
import Testing
@testable import InkCore

@Suite("IdleSendMachine (task B2)")
struct IdleSendMachineTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    private func restingMachine() -> IdleSendMachine {
        var m = IdleSendMachine()
        m.handle(.strokeBegan)
        m.handle(.strokeEnded(at: t0))
        return m
    }

    @Test("stroke at 2.9s cancels the send and aborts the speculative upload — nothing billed")
    func strokeAt2_9CancelsAndAborts() {
        var m = restingMachine()
        var effects: [SendEffect] = []
        effects += m.handle(.tick(now: t0.addingTimeInterval(2.0)))
        effects += m.handle(.tick(now: t0.addingTimeInterval(2.5)))
        // New stroke at 2.9s, before the 3.0s commit.
        effects += m.handle(.strokeBegan)

        #expect(m.state == .cancelled)
        #expect(effects.contains(.abortUpload))
        #expect(!effects.contains(.commitSend), "a cancelled send must never be billed")
    }

    @Test("rest to 3.0s emits exactly one commitSend")
    func restToCommitEmitsExactlyOneCommit() {
        var m = restingMachine()
        var commits = 0
        for offset in stride(from: 0.5, through: 6.0, by: 0.5) {
            commits += m.handle(.tick(now: t0.addingTimeInterval(offset))).filter { $0 == .commitSend }.count
        }
        #expect(commits == 1)
        #expect(m.state == .committed)
    }

    @Test("double-commit impossible even with repeated late ticks")
    func doubleCommitImpossible() {
        var m = restingMachine()
        let first = m.handle(.tick(now: t0.addingTimeInterval(3.0)))
        #expect(first == [.commitSend])
        for offset in [3.1, 4.0, 10.0, 100.0] {
            #expect(m.handle(.tick(now: t0.addingTimeInterval(offset))).isEmpty)
        }
    }

    @Test("speculative upload begins at 2.0s, before the 3.0s commit")
    func speculativeUploadAtTwoSeconds() {
        var m = restingMachine()
        #expect(m.handle(.tick(now: t0.addingTimeInterval(1.9))).isEmpty)
        #expect(m.handle(.tick(now: t0.addingTimeInterval(2.0))) == [.beginSpeculativeUpload])
        #expect(m.state == .speculating(since: t0))
        // Speculation is emitted once, not on every tick.
        #expect(m.handle(.tick(now: t0.addingTimeInterval(2.4))).isEmpty)
    }

    @Test("ticks that jump straight past 3.0s commit without a speculative upload")
    func tickJumpCommitsDirectly() {
        var m = restingMachine()
        let effects = m.handle(.tick(now: t0.addingTimeInterval(3.2)))
        #expect(effects == [.commitSend])
    }

    @Test("stroke during resting (before 2s) cancels without an upload to abort")
    func strokeDuringRestingCancelsQuietly() {
        var m = restingMachine()
        m.handle(.tick(now: t0.addingTimeInterval(1.0)))
        let effects = m.handle(.strokeBegan)
        #expect(m.state == .cancelled)
        #expect(effects.isEmpty, "no speculative upload existed, so nothing to abort")
    }

    @Test("cancelled machine resumes the cycle: strokeEnded → resting → commit")
    func cancelledResumesCycle() {
        var m = restingMachine()
        m.handle(.tick(now: t0.addingTimeInterval(2.0)))
        m.handle(.strokeBegan) // cancel at 2s+
        let t1 = t0.addingTimeInterval(10)
        m.handle(.strokeEnded(at: t1))
        #expect(m.state == .resting(since: t1))
        #expect(m.handle(.tick(now: t1.addingTimeInterval(3.0))) == [.commitSend])
    }

    @Test("ticks while inking or idle do nothing")
    func ticksOutsideRestDoNothing() {
        var m = IdleSendMachine()
        #expect(m.handle(.tick(now: t0)).isEmpty)
        m.handle(.strokeBegan)
        #expect(m.handle(.tick(now: t0.addingTimeInterval(50))).isEmpty)
        #expect(m.state == .inking)
    }

    @Test("reset returns to idle for the next exchange")
    func resetReturnsToIdle() {
        var m = restingMachine()
        m.handle(.tick(now: t0.addingTimeInterval(3.0)))
        m.reset()
        #expect(m.state == .idle)
        m.handle(.strokeBegan)
        #expect(m.state == .inking)
    }
}
