import Testing
import Foundation
@testable import VisioCore

private func unmute(_ channel: Channel) -> MuteCommand {
    .unmute(CallSessions.Key(channel: channel, tabId: 5))
}

@Test func muteAllGoesToEveryPipe() {
    let targets = MuteCommand.muteAll.targets(pipes: [1, 2], safariHasSession: false, safariRunning: true)
    #expect(targets == .init(pipes: [1, 2], safari: false))
}

@Test func muteAllReachesSafariOnlyWithASessionWhileItRuns() {
    #expect(MuteCommand.muteAll.targets(pipes: [], safariHasSession: true, safariRunning: true).safari)
    #expect(!MuteCommand.muteAll.targets(pipes: [], safariHasSession: true, safariRunning: false).safari)
    #expect(!MuteCommand.muteAll.targets(pipes: [], safariHasSession: false, safariRunning: true).safari)
}

@Test func unmuteGoesOnlyToItsPipe() {
    let targets = unmute(.pipe(2)).targets(pipes: [1, 2, 3], safariHasSession: true, safariRunning: true)
    #expect(targets == .init(pipes: [2], safari: false))
}

@Test func unmuteToSafariOnlyWhileItRuns() {
    #expect(unmute(.safari).targets(pipes: [1], safariHasSession: true, safariRunning: true) == .init(pipes: [], safari: true))
    #expect(unmute(.safari).targets(pipes: [1], safariHasSession: true, safariRunning: false) == .init(pipes: [], safari: false))
}

@Test func unmuteToAClosedPipeGoesNowhere() {
    let targets = unmute(.pipe(9)).targets(pipes: [1, 2], safariHasSession: true, safariRunning: true)
    #expect(targets == .init(pipes: [], safari: false))
}
