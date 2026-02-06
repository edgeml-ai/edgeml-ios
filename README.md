# EdgeML iOS SDK

A Swift SDK for federated learning on iOS devices with CoreML integration.

## Overview

The EdgeML iOS SDK enables iOS applications to participate in federated learning by:
- Registering devices with the EdgeML server
- Downloading and caching CoreML models
- Running on-device inference
- Participating in federated training rounds
- Syncing model updates in the background

## Requirements

- iOS 15.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add EdgeML to your project using Swift Package Manager:

```swift
dependencies: [
    .package(path: "../edgeml-ios")
]
```

Or add it through Xcode:
1. File -> Add Package Dependencies
2. Enter the package URL

## Quick Start

### 1. Initialize the Client

```swift
import EdgeML

let client = EdgeMLClient(
    apiKey: "your-api-key",
    orgId: "your-org-id",
    serverURL: URL(string: "https://api.edgeml.ai")!,
    configuration: .default
)
```

### 2. Register the Device

```swift
do {
    let registration = try await client.register(
        metadata: ["app_version": "1.0.0"]
    )
    print("Device registered: \(registration.deviceId)")
} catch {
    print("Registration failed: \(error)")
}
```

### 3. Download a Model

```swift
do {
    let model = try await client.downloadModel(modelId: "fraud_detection")
    print("Model downloaded: \(model.id) v\(model.version)")
} catch {
    print("Download failed: \(error)")
}
```

### 4. Run Inference

```swift
// Create input features
let input = try MLDictionaryFeatureProvider(dictionary: [
    "feature1": 0.5,
    "feature2": 1.0
])

// Run prediction
let prediction = try model.predict(input: input)

// Access results
if let output = prediction.featureValue(for: "prediction") {
    print("Prediction: \(output.doubleValue)")
}
```

### 5. Participate in Training

```swift
let result = try await client.participateInRound(
    modelId: "fraud_detection",
    dataProvider: { yourTrainingDataBatch },
    config: TrainingConfig(epochs: 1, batchSize: 32)
)
print("Training completed: \(result.trainingResult.sampleCount) samples")
```

### 6. Enable Background Training

```swift
// In AppDelegate or app initialization
BackgroundSync.registerBackgroundTasks()

// Enable background training
client.enableBackgroundTraining(
    modelId: "fraud_detection",
    dataProvider: { yourTrainingDataBatch },
    constraints: .default
)
```

## Configuration

### EdgeMLConfiguration

Customize SDK behavior with configuration options:

```swift
let config = EdgeMLConfiguration(
    maxRetryAttempts: 5,
    requestTimeout: 60,
    downloadTimeout: 300,
    enableLogging: true,
    logLevel: .debug,
    maxCacheSize: 500 * 1024 * 1024, // 500 MB
    autoCheckUpdates: true,
    updateCheckInterval: 3600, // 1 hour
    requireWiFiForDownload: true,
    requireChargingForTraining: true,
    minimumBatteryLevel: 0.2
)

let client = EdgeMLClient(
    apiKey: "your-api-key",
    orgId: "your-org-id",
    configuration: config
)
```

### Preset Configurations

```swift
// Development (verbose logging, relaxed constraints)
let devConfig = EdgeMLConfiguration.development

// Production (conservative settings, minimal logging)
let prodConfig = EdgeMLConfiguration.production
```

## Background Training

### Registration

Register background tasks in your `AppDelegate` or `@main` struct:

```swift
@main
struct YourApp: App {
    init() {
        BackgroundSync.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Info.plist Configuration

Add the background task identifiers to your Info.plist:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>ai.edgeml.training</string>
    <string>ai.edgeml.sync</string>
</array>
```

### Background Constraints

Customize when background training runs:

```swift
let constraints = BackgroundConstraints(
    requiresWiFi: true,
    requiresCharging: true,
    minimumBatteryLevel: 0.2,
    maxExecutionTime: 300
)

client.enableBackgroundTraining(
    modelId: "fraud_detection",
    dataProvider: { yourData },
    constraints: constraints
)
```

## Secure Storage

API keys and tokens are stored securely in the iOS Keychain:

```swift
let storage = SecureStorage()

// Store API key
try storage.storeAPIKey("your-api-key")

// Retrieve API key
let apiKey = try storage.getAPIKey()

// Clear all credentials
storage.clearAll()
```

## Runtime Device Auth

For production clients, mint short-lived device tokens from your backend and refresh them at runtime.

```swift
import EdgeML

let auth = DeviceAuthManager(
    baseURL: URL(string: "https://api.edgeml.io")!,
    orgId: "org_123",
    deviceIdentifier: "ios-device-abc"
)

// Bootstrap once with a backend-issued bootstrap bearer token
let tokenState = try await auth.bootstrap(bootstrapBearerToken: "token_from_backend")

// Get valid short-lived access token for API requests
let accessToken = try await auth.getAccessToken()
```

## Network Monitoring

Monitor network status for optimal operation:

```swift
let monitor = NetworkMonitor.shared

if monitor.isConnected {
    // Proceed with network operations
}

if monitor.isOnWiFi {
    // Large downloads are OK
}

// Add status change handler
let token = monitor.addHandler { isConnected in
    print("Network status changed: \(isConnected)")
}

// Remove handler when done
monitor.removeHandler(token)
```

## Error Handling

The SDK uses `EdgeMLError` for all error cases:

```swift
do {
    let model = try await client.downloadModel(modelId: "test")
} catch let error as EdgeMLError {
    switch error {
    case .networkUnavailable:
        print("Check your network connection")
    case .deviceNotRegistered:
        print("Please register the device first")
    case .modelNotFound(let modelId):
        print("Model not found: \(modelId)")
    case .checksumMismatch:
        print("Download corrupted, please retry")
    default:
        print(error.localizedDescription)
    }
}
```

## Model Caching

Models are automatically cached after download:

```swift
// Get cached model (no network required)
if let cachedModel = client.getCachedModel(modelId: "fraud_detection") {
    // Use cached model
}

// Check for updates
if let update = try await client.checkForUpdates(modelId: "fraud_detection") {
    if update.isRequired {
        // Download new version
        let newModel = try await client.downloadModel(
            modelId: "fraud_detection",
            version: update.newVersion
        )
    }
}

// Clear cache if needed
try client.clearCache()
```

## Architecture

```
edgeml-ios/
├── Sources/EdgeML/
│   ├── Client/
│   │   ├── EdgeMLClient.swift      # Main entry point
│   │   ├── Configuration.swift     # SDK configuration
│   │   ├── APIClient.swift         # Network layer
│   │   ├── APIModels.swift         # Request/response models
│   │   └── EdgeMLError.swift       # Error types
│   ├── Models/
│   │   ├── EdgeMLModel.swift       # CoreML wrapper
│   │   ├── ModelManager.swift      # Download & version control
│   │   └── ModelCache.swift        # Local storage
│   ├── Training/
│   │   └── FederatedTrainer.swift  # On-device training
│   ├── Sync/
│   │   └── BackgroundSync.swift    # Background tasks
│   └── Utils/
│       ├── SecureStorage.swift     # Keychain access
│       ├── NetworkMonitor.swift    # Connectivity
│       └── Logger.swift            # Logging
├── Tests/EdgeMLTests/
└── Examples/EdgeMLDemo/
```

## License

Copyright 2024 EdgeML Team. All rights reserved.
