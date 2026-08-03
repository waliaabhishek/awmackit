import XCTest

@testable import PowerTools

final class JavaScriptURLTransformerTests: XCTestCase {
    func testTransformRunsInHelperProcess() async throws {
        let input = try XCTUnwrap(URL(string: "https://example.com/original"))
        let output = try await JavaScriptURLTransformer().transform(
            url: input,
            sourceApplication: nil,
            script: #"$.url.pathname = "/changed";"#
        )
        XCTAssertEqual(output.absoluteString, "https://example.com/changed")
    }

    func testInfiniteTransformIsTerminated() async throws {
        let input = try XCTUnwrap(URL(string: "https://example.com"))
        let start = ContinuousClock.now
        do {
            _ = try await JavaScriptURLTransformer().transform(
                url: input,
                sourceApplication: nil,
                script: "while (true) {}"
            )
            XCTFail("The transform should have exceeded its deadline.")
        } catch is AsyncProcessRunnerError {
            // Expected.
        }
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))
    }

    func testTransformCannotEscapeWebSchemes() async throws {
        let input = try XCTUnwrap(URL(string: "https://example.com"))
        do {
            _ = try await JavaScriptURLTransformer().transform(
                url: input,
                sourceApplication: nil,
                script: #"$.url.href = "file:///etc/passwd";"#
            )
            XCTFail("Transforms must remain HTTP or HTTPS URLs.")
        } catch JavaScriptURLTransformer.TransformError.invalidOutput {
            // Expected.
        }
    }
}
