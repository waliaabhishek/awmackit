public actor AsyncGate {
    private var isOccupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func enter() async {
        if !isOccupied {
            isOccupied = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    public func leave() {
        if waiters.isEmpty {
            isOccupied = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
