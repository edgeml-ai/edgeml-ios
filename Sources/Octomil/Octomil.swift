/// Octomil iOS SDK
///
/// A Swift SDK for federated learning on iOS devices with CoreML integration.
///
/// # Overview
///
/// Octomil provides a complete solution for:
/// - Device registration with the Octomil server
/// - Model download and caching with version management
/// - On-device inference using CoreML
/// - Federated training with weight extraction and upload
/// - Background task scheduling for training rounds
///
/// # Quick Start
///
/// ```swift
/// import Octomil
///
/// let client = OctomilClient(
///     deviceAccessToken: "<short-lived-device-token>",
///     orgId: "org_123",
///     serverURL: URL(string: "https://api.octomil.com")!
/// )
///
/// // Register device
/// let registration = try await client.register()
///
/// // Download model
/// let model = try await client.downloadModel(modelId: "fraud_detection")
///
/// // Run inference
/// let prediction = try model.predict(input: inputFeatures)
/// ```
///
/// # Requirements
///
/// - iOS 15.0+
/// - Swift 5.9+
///
/// # Features
///
/// - **Model Management**: Download, cache, and version-check CoreML models
/// - **Federated Training**: On-device training with weight extraction
/// - **Background Sync**: Automatic training during idle periods
/// - **Secure Storage**: Device token and credential management via Keychain
/// - **Network Resilience**: Automatic retries and offline support

@_exported import Foundation
@_exported import CoreML
