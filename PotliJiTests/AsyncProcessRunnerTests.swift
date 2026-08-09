import XCTest

@testable import PotliJi

final class AsyncProcessRunnerTests: XCTestCase {
    func testCapturesProcessOutput() async throws {
        let output = try await AsyncProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"],
            timeout: 2
        )
        XCTAssertEqual(output.terminationStatus, 0)
        XCTAssertEqual(String(decoding: output.standardOutput, as: UTF8.self), "hello\n")
    }

    func testTerminatesProcessAtDeadline() async throws {
        let start = ContinuousClock.now
        do {
            _ = try await AsyncProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "while :; do :; done"],
                timeout: 0.1
            )
            XCTFail("The process should have timed out.")
        } catch is AsyncProcessRunnerError {
            // Expected.
        }
        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
    }

    func testDrainsOutputLargerThanPipeCapacityWithoutDeadlocking() async throws {
        let output = try await AsyncProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 131072 /dev/zero"],
            timeout: 2
        )
        XCTAssertEqual(output.standardOutput.count, 131_072)
    }

    func testRejectsUnboundedHelperOutput() async throws {
        do {
            _ = try await AsyncProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "head -c 1100000 /dev/zero"],
                timeout: 2
            )
            XCTFail("Output beyond the capture limit must be rejected.")
        } catch AsyncProcessRunnerError.outputTooLarge {
            // Expected.
        }
    }
}
