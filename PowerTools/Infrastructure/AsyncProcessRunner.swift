import Darwin
import Foundation

struct ProcessOutput: Sendable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data
}

enum AsyncProcessRunnerError: LocalizedError {
    case timedOut(TimeInterval)
    case outputTooLarge

    var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            "The helper process exceeded its \(seconds.formatted()) second execution limit."
        case .outputTooLarge:
            "The helper process produced more than 1 MB of output."
        }
    }
}

enum AsyncProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String] = [],
        input: Data? = nil,
        timeout: TimeInterval
    ) async throws -> ProcessOutput {
        let work = Task.detached(priority: .userInitiated) {
            try await runOffMain(
                executableURL: executableURL,
                arguments: arguments,
                input: input,
                timeout: timeout
            )
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private static func runOffMain(
        executableURL: URL,
        arguments: [String],
        input: Data?,
        timeout: TimeInterval
    ) async throws -> ProcessOutput {
        let process = Process()
        let processBox = ProcessBox(process)
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = input == nil ? nil : Pipe()
        let termination = ProcessTermination()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe
        process.terminationHandler = { completedProcess in
            termination.complete(status: completedProcess.terminationStatus)
        }

        try process.run()
        let outputReader = PipeReader(outputPipe.fileHandleForReading)
        let errorReader = PipeReader(errorPipe.fileHandleForReading)
        let outputTask = Task.detached(priority: .utility) { outputReader.readToEnd() }
        let errorTask = Task.detached(priority: .utility) { errorReader.readToEnd() }

        let inputTask: Task<Void, Never>?
        if let input, let inputPipe {
            let writer = PipeWriter(inputPipe.fileHandleForWriting)
            inputTask = Task.detached(priority: .utility) { writer.writeAndClose(input) }
        } else {
            inputTask = nil
        }

        enum Outcome: Sendable {
            case completed(Int32)
            case timedOut(Int32)
            case cancelled(Int32)
        }

        let outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                .completed(await termination.wait())
            }
            group.addTask {
                do {
                    try await Task.sleep(for: .seconds(timeout))
                    return .timedOut(0)
                } catch {
                    return .cancelled(0)
                }
            }

            let first = await group.next() ?? .cancelled(0)
            let resolved: Outcome
            switch first {
            case .completed:
                resolved = first
            case .timedOut:
                processBox.terminate()
                Task.detached(priority: .utility) {
                    try? await Task.sleep(for: .milliseconds(250))
                    processBox.forceKillIfRunning()
                }
                resolved = .timedOut(await termination.wait())
            case .cancelled:
                processBox.terminate()
                Task.detached(priority: .utility) {
                    try? await Task.sleep(for: .milliseconds(250))
                    processBox.forceKillIfRunning()
                }
                resolved = .cancelled(await termination.wait())
            }
            group.cancelAll()
            return resolved
        }

        enum TerminalFailure {
            case timedOut
            case cancelled
        }

        let status: Int32
        let terminalFailure: TerminalFailure?
        switch outcome {
        case .completed(let completedStatus):
            status = completedStatus
            terminalFailure = nil
        case .timedOut(let completedStatus):
            status = completedStatus
            terminalFailure = .timedOut
        case .cancelled(let completedStatus):
            status = completedStatus
            terminalFailure = .cancelled
        }

        _ = await inputTask?.value
        let standardOutput = await outputTask.value
        let standardError = await errorTask.value
        switch terminalFailure {
        case .timedOut:
            throw AsyncProcessRunnerError.timedOut(timeout)
        case .cancelled:
            throw CancellationError()
        case nil:
            break
        }
        guard !standardOutput.exceededLimit, !standardError.exceededLimit else {
            throw AsyncProcessRunnerError.outputTooLarge
        }

        return ProcessOutput(
            terminationStatus: status,
            standardOutput: standardOutput.data,
            standardError: standardError.data
        )
    }
}

private struct PipeReadResult: Sendable {
    let data: Data
    let exceededLimit: Bool
}

private final class PipeReader: @unchecked Sendable {
    private static let maximumCapturedBytes = 1_024 * 1_024
    private let handle: FileHandle

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    func readToEnd() -> PipeReadResult {
        var captured = Data()
        var exceededLimit = false
        while true {
            let chunk = handle.readData(ofLength: 64 * 1_024)
            guard !chunk.isEmpty else { break }
            let remaining = Self.maximumCapturedBytes - captured.count
            if remaining > 0 {
                captured.append(chunk.prefix(remaining))
            }
            if chunk.count > remaining { exceededLimit = true }
        }
        return PipeReadResult(data: captured, exceededLimit: exceededLimit)
    }
}

private final class PipeWriter: @unchecked Sendable {
    private let handle: FileHandle

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    func writeAndClose(_ data: Data) {
        handle.write(data)
        try? handle.close()
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()

    init(_ process: Process) {
        self.process = process
    }

    func terminate() {
        lock.withLock {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    func forceKillIfRunning() {
        lock.withLock {
            guard process.isRunning else { return }
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }
}

private final class ProcessTermination: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var waiters: [CheckedContinuation<Int32, Never>] = []

    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            let completedStatus = lock.withLock { () -> Int32? in
                if let status { return status }
                waiters.append(continuation)
                return nil
            }
            if let completedStatus {
                continuation.resume(returning: completedStatus)
            }
        }
    }

    func complete(status: Int32) {
        let continuations = lock.withLock { () -> [CheckedContinuation<Int32, Never>] in
            guard self.status == nil else { return [] }
            self.status = status
            defer { waiters.removeAll() }
            return waiters
        }
        for continuation in continuations {
            continuation.resume(returning: status)
        }
    }
}
