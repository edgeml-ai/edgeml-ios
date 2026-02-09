import Foundation
import CoreML

// MARK: - Event Tracking

extension EdgeMLClient {

    /// Tracks an event for an experiment.
    ///
    /// - Parameters:
    ///   - experimentId: Experiment identifier.
    ///   - eventName: Name of the event.
    ///   - properties: Event properties.
    public func trackEvent(
        experimentId: String,
        eventName: String,
        properties: [String: String] = [:]
    ) async throws {
        let event = TrackingEvent(
            name: eventName,
            properties: properties,
            timestamp: Date()
        )

        try await apiClient.trackEvent(experimentId: experimentId, event: event)
    }
}

// MARK: - Background Operations

extension EdgeMLClient {

    /// Enables background training when conditions are met.
    ///
    /// Background training runs during device idle time when:
    /// - Device is connected to power (optional)
    /// - Network is available
    /// - Battery level is sufficient
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - constraints: Background execution constraints.
    public func enableBackgroundTraining(
        modelId: String,
        dataProvider: @escaping @Sendable () -> MLBatchProvider,
        constraints: BackgroundConstraints = .standard
    ) {
        let sync = BackgroundSync.shared
        sync.configure(
            modelId: modelId,
            dataProvider: dataProvider,
            constraints: constraints,
            client: self
        )
        sync.scheduleNextTraining()

        if configuration.enableLogging {
            logger.info("Background training enabled for model: \(modelId)")
        }
    }

    /// Disables background training.
    public func disableBackgroundTraining() {
        BackgroundSync.shared.cancelScheduledTraining()

        if configuration.enableLogging {
            logger.info("Background training disabled")
        }
    }
}

// MARK: - Inference Reporting Context

extension EdgeMLClient {

    /// Groups the common parameters needed for inference event reporting.
    struct InferenceReportingContext {
        let apiClient: APIClient
        let deviceId: String?
        let model: EdgeMLModel
        let modality: Modality
        let sessionId: String
        let orgId: String
    }

    func reportInferenceStarted(
        context: InferenceReportingContext
    ) {
        guard let deviceId = context.deviceId else { return }
        let ctx = context
        Task {
            let eventCtx = InferenceEventContext(
                deviceId: deviceId,
                modelId: ctx.model.id,
                version: ctx.model.version,
                modality: ctx.modality.rawValue,
                sessionId: ctx.sessionId
            )
            let event = InferenceEventRequest(
                context: eventCtx,
                eventType: "generation_started",
                timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                orgId: ctx.orgId
            )
            try? await ctx.apiClient.reportInferenceEvent(event)
        }
    }

    func buildInferenceStream(
        stream: AsyncThrowingStream<InferenceChunk, Error>,
        getResult: @escaping @Sendable () -> StreamingInferenceResult?,
        context: InferenceReportingContext
    ) -> AsyncThrowingStream<InferenceChunk, Error> {
        return AsyncThrowingStream<InferenceChunk, Error> { continuation in
            let task = Task {
                var failed = false
                do {
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                } catch {
                    failed = true
                    continuation.finish(throwing: error)
                }

                if !failed {
                    continuation.finish()
                }

                // Report completion event
                if let deviceId = context.deviceId, let result = getResult() {
                    let metrics = InferenceEventMetrics(
                        ttfcMs: result.ttfcMs,
                        totalChunks: result.totalChunks,
                        totalDurationMs: result.totalDurationMs,
                        throughput: result.throughput
                    )
                    let eventCtx = InferenceEventContext(
                        deviceId: deviceId,
                        modelId: context.model.id,
                        version: context.model.version,
                        modality: context.modality.rawValue,
                        sessionId: context.sessionId
                    )
                    let eventType = failed
                        ? "generation_failed"
                        : "generation_completed"
                    let event = InferenceEventRequest(
                        context: eventCtx,
                        eventType: eventType,
                        timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                        metrics: metrics,
                        orgId: context.orgId
                    )
                    try? await context.apiClient.reportInferenceEvent(event)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
