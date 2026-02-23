import Foundation

/// Client for federated analytics queries across federation members.
///
/// Provides methods for running cross-site statistical analyses including
/// descriptive statistics, t-tests, chi-square tests, and ANOVA.
///
/// Use ``OctomilClient/analytics(federationId:)`` to create an instance.
public final class FederatedAnalyticsClient: Sendable {

    private let apiClient: APIClient
    private let federationId: String
    private var basePath: String { "api/v1/federations/\(federationId)/analytics" }

    /// Creates a new federated analytics client.
    /// - Parameters:
    ///   - apiClient: The API client for network requests.
    ///   - federationId: The federation to run analytics against.
    public init(apiClient: APIClient, federationId: String) {
        self.apiClient = apiClient
        self.federationId = federationId
    }

    // MARK: - Statistical Analyses

    /// Runs descriptive statistics across groups in the federation.
    ///
    /// - Parameters:
    ///   - variable: The variable to analyze.
    ///   - groupBy: How to group the data ("device_group" or "federation_member").
    ///   - groupIds: Optional list of specific group IDs to include.
    ///   - includePercentiles: Whether to include percentile calculations.
    ///   - filters: Optional filters to apply.
    /// - Returns: Descriptive statistics result.
    /// - Throws: `OctomilError` if the request fails.
    public func descriptive(
        variable: String,
        groupBy: String = "device_group",
        groupIds: [String]? = nil,
        includePercentiles: Bool = true,
        filters: AnalyticsFilter? = nil
    ) async throws -> DescriptiveResult {
        let body = DescriptiveRequest(
            variable: variable,
            groupBy: groupBy,
            groupIds: groupIds,
            includePercentiles: includePercentiles,
            filters: filters
        )
        return try await apiClient.postJSON(path: "\(basePath)/descriptive", body: body)
    }

    /// Runs a two-sample t-test between two groups.
    ///
    /// - Parameters:
    ///   - variable: The variable to test.
    ///   - groupA: First group identifier.
    ///   - groupB: Second group identifier.
    ///   - confidenceLevel: Confidence level for the test (default 0.95).
    ///   - filters: Optional filters to apply.
    /// - Returns: T-test result.
    /// - Throws: `OctomilError` if the request fails.
    public func tTest(
        variable: String,
        groupA: String,
        groupB: String,
        confidenceLevel: Double = 0.95,
        filters: AnalyticsFilter? = nil
    ) async throws -> TTestResult {
        let body = TTestRequestBody(
            variable: variable,
            groupA: groupA,
            groupB: groupB,
            confidenceLevel: confidenceLevel,
            filters: filters
        )
        return try await apiClient.postJSON(path: "\(basePath)/t-test", body: body)
    }

    /// Runs a chi-square test of independence.
    ///
    /// - Parameters:
    ///   - variable1: First categorical variable.
    ///   - variable2: Second categorical variable.
    ///   - groupIds: Optional list of group IDs to include.
    ///   - confidenceLevel: Confidence level for the test (default 0.95).
    ///   - filters: Optional filters to apply.
    /// - Returns: Chi-square test result.
    /// - Throws: `OctomilError` if the request fails.
    public func chiSquare(
        variable1: String,
        variable2: String,
        groupIds: [String]? = nil,
        confidenceLevel: Double = 0.95,
        filters: AnalyticsFilter? = nil
    ) async throws -> ChiSquareResult {
        let body = ChiSquareRequestBody(
            variable1: variable1,
            variable2: variable2,
            groupIds: groupIds,
            confidenceLevel: confidenceLevel,
            filters: filters
        )
        return try await apiClient.postJSON(path: "\(basePath)/chi-square", body: body)
    }

    /// Runs a one-way ANOVA test across groups.
    ///
    /// - Parameters:
    ///   - variable: The variable to analyze.
    ///   - groupBy: How to group the data ("device_group" or "federation_member").
    ///   - groupIds: Optional list of specific group IDs to include.
    ///   - confidenceLevel: Confidence level for the test (default 0.95).
    ///   - postHoc: Whether to include post-hoc pairwise comparisons.
    ///   - filters: Optional filters to apply.
    /// - Returns: ANOVA result.
    /// - Throws: `OctomilError` if the request fails.
    public func anova(
        variable: String,
        groupBy: String = "device_group",
        groupIds: [String]? = nil,
        confidenceLevel: Double = 0.95,
        postHoc: Bool = true,
        filters: AnalyticsFilter? = nil
    ) async throws -> AnovaResult {
        let body = AnovaRequestBody(
            variable: variable,
            groupBy: groupBy,
            groupIds: groupIds,
            confidenceLevel: confidenceLevel,
            postHoc: postHoc,
            filters: filters
        )
        return try await apiClient.postJSON(path: "\(basePath)/anova", body: body)
    }

    // MARK: - Query History

    /// Lists past analytics queries for this federation.
    ///
    /// - Parameters:
    ///   - limit: Maximum number of queries to return (default 50).
    ///   - offset: Offset for pagination (default 0).
    /// - Returns: List response with queries and total count.
    /// - Throws: `OctomilError` if the request fails.
    public func listQueries(
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> AnalyticsQueryListResponse {
        return try await apiClient.getJSON(
            path: "\(basePath)/queries",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
        )
    }

    /// Gets a specific analytics query by ID.
    ///
    /// - Parameter queryId: The query identifier.
    /// - Returns: The analytics query with its result.
    /// - Throws: `OctomilError` if the request fails.
    public func getQuery(queryId: String) async throws -> AnalyticsQuery {
        return try await apiClient.getJSON(path: "\(basePath)/queries/\(queryId)")
    }
}
