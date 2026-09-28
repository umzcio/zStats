import Testing
@testable import StatsCore

@MainActor @Test func coalescedUpdateUsesLatestStateOncePerBurst() {
    var queued: [@MainActor () -> Void] = []
    var state = 0
    var rendered: [Int] = []
    let update = CoalescedUpdate(enqueue: { queued.append($0) }) {
        rendered.append(state)
    }

    for value in 1...6 {
        state = value
        update.request()
    }

    #expect(queued.count == 1)
    queued.removeFirst()()
    #expect(rendered == [6])

    state = 7
    update.request()
    state = 8
    update.request()
    #expect(queued.count == 1)
    queued.removeFirst()()
    #expect(rendered == [6, 8])
}

@MainActor @Test func coalescedUpdatePreservesReentrantRequest() {
    var queued: [@MainActor () -> Void] = []
    var calls = 0
    var update: CoalescedUpdate!
    update = CoalescedUpdate(enqueue: { queued.append($0) }) {
        calls += 1
        if calls == 1 { update.request() }
    }

    update.request()
    queued.removeFirst()()
    #expect(calls == 1)
    #expect(queued.count == 1)

    queued.removeFirst()()
    #expect(calls == 2)
    #expect(queued.isEmpty)
}

@MainActor @Test func queuedUpdateDoesNotRetainItsOwner() {
    final class Owner {
        var calls = 0
        var update: CoalescedUpdate?
    }

    var queued: [@MainActor () -> Void] = []
    weak var releasedOwner: Owner?
    do {
        let owner = Owner()
        owner.update = CoalescedUpdate(enqueue: { queued.append($0) }) { [weak owner] in
            owner?.calls += 1
        }
        releasedOwner = owner
        owner.update?.request()
    }

    #expect(releasedOwner == nil)
    #expect(queued.count == 1)
    queued.removeFirst()()
    #expect(releasedOwner == nil)
}
