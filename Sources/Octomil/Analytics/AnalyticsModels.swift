import Foundation

// MARK: - Request Models

/// Filter criteria for analytics queries.
public struct AnalyticsFilter: Codable, Sendable {
    public let startTime: String?
    public let endTime: String?
    public let devicePlatform: String?
    public let minSampleCount: Int?

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case devicePlatform = "device_platform"
        case minSampleCount = "min_sample_count"
    }

    public init(
        startTime: String? = nil,
        endTime: String? = nil,
        devicePlatform: String? = nil,
        minSampleCount: Int? = nil
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.devicePlatform = devicePlatform
        self.minSampleCount = minSampleCount
    }
}

// MARK: - Descriptive

struct DescriptiveRequest: Encodable {
    let variable: String
    let groupBy: String
    let groupIds: [String]?
    let includePercentiles: Bool
    let filters: AnalyticsFilter?

    enum CodingKeys: String, CodingKey {
        case variable
        case groupBy = "group_by"
        case groupIds = "group_ids"
        case includePercentiles = "include_percentiles"
        case filters
    }
}

/// Result of a descriptive statistics query.
public struct DescriptiveResult: Codable, Sendable {
    public let variable: String
    public let groupBy: String
    public let groups: [GroupStats]

    enum CodingKeys: String, CodingKey {
        case variable
        case groupBy = "group_by"
        case groups
    }
}

/// Descriptive statistics for a single group.
public struct GroupStats: Codable, Sendable {
    public let groupId: String
    public let count: Int
    public let mean: Double
    public let median: Double?
    public let stdDev: Double?
    public let min: Double?
    public let max: Double?
    public let percentiles: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case count
        case mean
        case median
        case stdDev = "std_dev"
        case min
        case max
        case percentiles
    }
}

// MARK: - T-Test

struct TTestRequestBody: Encodable {
    let variable: String
    let groupA: String
    let groupB: String
    let confidenceLevel: Double
    let filters: AnalyticsFilter?

    enum CodingKeys: String, CodingKey {
        case variable
        case groupA = "group_a"
        case groupB = "group_b"
        case confidenceLevel = "confidence_level"
        case filters
    }
}

/// Result of a two-sample t-test.
public struct TTestResult: Codable, Sendable {
    public let variable: String
    public let groupA: String
    public let groupB: String
    public let tStatistic: Double
    public let pValue: Double
    public let degreesOfFreedom: Double
    public let confidenceInterval: ConfidenceInterval?
    public let significant: Bool

    enum CodingKeys: String, CodingKey {
        case variable
        case groupA = "group_a"
        case groupB = "group_b"
        case tStatistic = "t_statistic"
        case pValue = "p_value"
        case degreesOfFreedom = "degrees_of_freedom"
        case confidenceInterval = "confidence_interval"
        case significant
    }
}

/// Confidence interval for a statistical test.
public struct ConfidenceInterval: Codable, Sendable {
    public let lower: Double
    public let upper: Double
    public let level: Double
}

// MARK: - Chi-Square

struct ChiSquareRequestBody: Encodable {
    let variable1: String
    let variable2: String
    let groupIds: [String]?
    let confidenceLevel: Double
    let filters: AnalyticsFilter?

    enum CodingKeys: String, CodingKey {
        case variable1 = "variable_1"
        case variable2 = "variable_2"
        case groupIds = "group_ids"
        case confidenceLevel = "confidence_level"
        case filters
    }
}

/// Result of a chi-square test of independence.
public struct ChiSquareResult: Codable, Sendable {
    public let variable1: String
    public let variable2: String
    public let chiSquareStatistic: Double
    public let pValue: Double
    public let degreesOfFreedom: Int
    public let significant: Bool
    public let cramersV: Double?

    enum CodingKeys: String, CodingKey {
        case variable1 = "variable_1"
        case variable2 = "variable_2"
        case chiSquareStatistic = "chi_square_statistic"
        case pValue = "p_value"
        case degreesOfFreedom = "degrees_of_freedom"
        case significant
        case cramersV = "cramers_v"
    }
}

// MARK: - ANOVA

struct AnovaRequestBody: Encodable {
    let variable: String
    let groupBy: String
    let groupIds: [String]?
    let confidenceLevel: Double
    let postHoc: Bool
    let filters: AnalyticsFilter?

    enum CodingKeys: String, CodingKey {
        case variable
        case groupBy = "group_by"
        case groupIds = "group_ids"
        case confidenceLevel = "confidence_level"
        case postHoc = "post_hoc"
        case filters
    }
}

/// Result of a one-way ANOVA test.
public struct AnovaResult: Codable, Sendable {
    public let variable: String
    public let groupBy: String
    public let fStatistic: Double
    public let pValue: Double
    public let degreesOfFreedomBetween: Int
    public let degreesOfFreedomWithin: Int
    public let significant: Bool
    public let postHocPairs: [PostHocPair]?

    enum CodingKeys: String, CodingKey {
        case variable
        case groupBy = "group_by"
        case fStatistic = "f_statistic"
        case pValue = "p_value"
        case degreesOfFreedomBetween = "degrees_of_freedom_between"
        case degreesOfFreedomWithin = "degrees_of_freedom_within"
        case significant
        case postHocPairs = "post_hoc_pairs"
    }
}

/// Post-hoc pairwise comparison result.
public struct PostHocPair: Codable, Sendable {
    public let groupA: String
    public let groupB: String
    public let pValue: Double
    public let significant: Bool

    enum CodingKeys: String, CodingKey {
        case groupA = "group_a"
        case groupB = "group_b"
        case pValue = "p_value"
        case significant
    }
}

// MARK: - Query History

/// A saved analytics query with its result.
public struct AnalyticsQuery: Codable, Sendable {
    public let id: String
    public let federationId: String
    public let queryType: String
    public let variable: String
    public let groupBy: String
    public let status: String
    public let result: [String: AnyCodable]?
    public let errorMessage: String?
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case federationId = "federation_id"
        case queryType = "query_type"
        case variable
        case groupBy = "group_by"
        case status
        case result
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Response for listing analytics queries.
public struct AnalyticsQueryListResponse: Decodable, Sendable {
    public let queries: [AnalyticsQuery]
    public let total: Int
}
