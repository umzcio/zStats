public struct ErrorEpisodeTracker: Sendable {
    private var isActive = false

    public init() {}

    public mutating func notification(for error: String?) -> String? {
        guard let error else {
            isActive = false
            return nil
        }
        guard !isActive else { return nil }
        isActive = true
        return error
    }
}
