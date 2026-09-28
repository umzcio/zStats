@MainActor public final class CoalescedUpdate {
    public typealias Enqueue = (@escaping @MainActor () -> Void) -> Void

    private let enqueue: Enqueue
    private let action: @MainActor () -> Void
    private var pending = false

    public init(enqueue: @escaping Enqueue, action: @escaping @MainActor () -> Void) {
        self.enqueue = enqueue
        self.action = action
    }

    public func request() {
        guard !pending else { return }
        pending = true
        enqueue { [weak self] in
            guard let self else { return }
            self.pending = false
            self.action()
        }
    }
}
