import Foundation
import XCTest
@testable import Octomil

/// Tests for ``DeepLinkHandler`` URL parsing and ``DeepLinkAction`` cases.
final class DeepLinkHandlerTests: XCTestCase {

    // MARK: - Valid Pair URLs

    func testParseValidPairURLWithTokenAndHost() {
        let url = URL(string: "octomil://pair?token=abc123&host=https://api.octomil.com")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertEqual(action, .pair(token: "abc123", host: "https://api.octomil.com"))
    }

    func testParseValidPairURLWithTokenOnly() {
        let url = URL(string: "octomil://pair?token=my-secret-token")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertEqual(action, .pair(token: "my-secret-token", host: nil))
    }

    func testParseValidPairURLWithCustomHost() {
        let url = URL(string: "octomil://pair?token=t1&host=https://staging.octomil.com:8443")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertEqual(action, .pair(token: "t1", host: "https://staging.octomil.com:8443"))
    }

    func testParseValidPairURLWithLongToken() {
        let longToken = String(repeating: "a", count: 128)
        let url = URL(string: "octomil://pair?token=\(longToken)")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertEqual(action, .pair(token: longToken, host: nil))
    }

    func testParseValidPairURLWithExtraQueryParams() {
        // Extra query params should be ignored, not cause a failure
        let url = URL(string: "octomil://pair?token=abc&host=https://api.octomil.com&extra=value")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertEqual(action, .pair(token: "abc", host: "https://api.octomil.com"))
    }

    func testParseValidPairURLParameterOrder() {
        // host before token should still work
        let url = URL(string: "octomil://pair?host=https://api.octomil.com&token=xyz")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertEqual(action, .pair(token: "xyz", host: "https://api.octomil.com"))
    }

    // MARK: - Missing Token

    func testParsePairURLWithoutTokenReturnsNil() {
        let url = URL(string: "octomil://pair?host=https://api.octomil.com")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertNil(action, "Missing token should return nil")
    }

    func testParsePairURLWithEmptyTokenReturnsNil() {
        let url = URL(string: "octomil://pair?token=&host=https://api.octomil.com")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertNil(action, "Empty token should return nil")
    }

    func testParsePairURLWithNoQueryParamsReturnsNil() {
        let url = URL(string: "octomil://pair")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertNil(action, "No query params should return nil")
    }

    // MARK: - Wrong Scheme

    func testParseHTTPSSchemeReturnsNil() {
        let url = URL(string: "https://pair?token=abc")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertNil(action, "Non-octomil scheme should return nil")
    }

    func testParseHTTPSchemeReturnsNil() {
        let url = URL(string: "http://pair?token=abc")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertNil(action, "HTTP scheme should return nil")
    }

    func testParseOtherSchemeReturnsNil() {
        let url = URL(string: "myapp://pair?token=abc")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertNil(action, "Custom non-octomil scheme should return nil")
    }

    // MARK: - Unknown Action

    func testParseUnknownHostReturnsUnknown() {
        let url = URL(string: "octomil://settings?theme=dark")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertEqual(action, .unknown(url: url))
    }

    func testParseUnknownActionWithNoHost() {
        // octomil:///something — nil host in URLComponents
        let url = URL(string: "octomil:///path?token=abc")!
        let action = DeepLinkHandler.parse(url: url)

        // url.host is nil for this URL, which does not match "pair"
        XCTAssertEqual(action, .unknown(url: url))
    }

    func testParseEmptyHostReturnsUnknown() {
        // octomil://?token=abc — host is empty string on some platforms
        let url = URL(string: "octomil://?token=abc")!
        let action = DeepLinkHandler.parse(url: url)

        // url.host may be nil or empty; either way it is not "pair"
        if let action {
            switch action {
            case .unknown:
                break // expected
            default:
                XCTFail("Expected .unknown for empty host, got \(action)")
            }
        }
        // nil is also acceptable (no host means nothing to parse)
    }

    // MARK: - Scheme Constant

    func testSchemeConstant() {
        XCTAssertEqual(DeepLinkHandler.scheme, "octomil")
    }

    // MARK: - DeepLinkAction Equatable

    func testDeepLinkActionEquality() {
        let a = DeepLinkAction.pair(token: "abc", host: "https://api.octomil.com")
        let b = DeepLinkAction.pair(token: "abc", host: "https://api.octomil.com")
        XCTAssertEqual(a, b)
    }

    func testDeepLinkActionInequality() {
        let a = DeepLinkAction.pair(token: "abc", host: nil)
        let b = DeepLinkAction.pair(token: "xyz", host: nil)
        XCTAssertNotEqual(a, b)
    }

    func testDeepLinkActionUnknownEquality() {
        let url = URL(string: "octomil://foo")!
        XCTAssertEqual(DeepLinkAction.unknown(url: url), DeepLinkAction.unknown(url: url))
    }

    func testDeepLinkActionDifferentCasesNotEqual() {
        let url = URL(string: "octomil://pair?token=abc")!
        let pair = DeepLinkAction.pair(token: "abc", host: nil)
        let unknown = DeepLinkAction.unknown(url: url)
        XCTAssertNotEqual(pair, unknown)
    }

    // MARK: - URL-Encoded Token

    func testParseURLEncodedToken() {
        // Tokens with special characters should be URL-decoded
        let url = URL(string: "octomil://pair?token=abc%2B123%3D%3D")!
        let action = DeepLinkHandler.parse(url: url)

        XCTAssertEqual(action, .pair(token: "abc+123==", host: nil))
    }
}
