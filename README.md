# EdgeML iOS SDK

Official iOS SDK for the EdgeML federated learning platform.

## Features

- Automatic Device Registration - Collects and sends complete hardware metadata
- Real-Time Monitoring - Tracks battery level, network type, and system constraints
- Stable Device IDs - Uses IDFV (Identifier For Vendor)
- CoreML Optimization - Leverages Neural Engine for on-device training
- Privacy-First - All training happens on-device

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/edgeml-ai/edgeml-ios.git", from: "1.1.0")
]
```

### CocoaPods

```ruby
pod 'EdgeML', '~> 1.1'
```

## Quick Start

```swift
import EdgeML

// Collect device information
let device = DeviceInfo()

// Get registration payload
let registrationData = device.toRegistrationDict()
print("Device ID: \(device.deviceId)")

// Get current metadata (battery, network)
let metadata = device.updateMetadata()
print("Battery: \(metadata["battery_level"] ?? "unknown")%")
print("Network: \(metadata["network_type"] ?? "unknown")")
```

## Device Information Collected

### Hardware
- Manufacturer: "Apple"
- Model: Device model code (e.g., "iPhone15,2")
- CPU Architecture: "arm64"
- Total Memory (MB)
- Available Storage (MB)
- Neural Engine Available (boolean)

### Runtime Constraints
- Battery Level (0-100%)
- Network Type (wifi, cellular, offline)

### System Info
- Platform: "ios"
- iOS Version
- Locale and Region
- Timezone

## Integration Example

```swift
import Foundation
import EdgeML

class EdgeMLClient {
    private let baseURL: String
    private let deviceToken: String
    private let device = DeviceInfo()
    private var deviceServerId: String?

    // deviceToken should be short-lived and issued by your backend.
    init(deviceToken: String, baseURL: String = "https://api.edgeml.io") {
        self.deviceToken = deviceToken
        self.baseURL = baseURL
    }

    func register(orgId: String) async throws -> String {
        var data = device.toRegistrationDict()
        data["org_id"] = orgId
        data["sdk_version"] = "1.1.0"

        let url = URL(string: "\(baseURL)/api/v1/devices/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: data)

        let (responseData, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode([String: String].self, from: responseData)

        self.deviceServerId = response["id"]
        return response["id"] ?? ""
    }

    func sendHeartbeat() async throws {
        guard let deviceId = deviceServerId else {
            throw NSError(domain: "EdgeML", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Device not registered"
            ])
        }

        let metadata = device.updateMetadata()

        let url = URL(string: "\(baseURL)/api/v1/devices/\(deviceId)/heartbeat")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["metadata": metadata])

        let _ = try await URLSession.shared.data(for: request)
    }
}

// Usage
let client = EdgeMLClient(deviceToken: "short_lived_token_from_backend")
Task {
    let deviceId = try await client.register(orgId: "your_org_id")
    print("Registered with ID: \(deviceId)")

    // Send periodic heartbeats
    try await client.sendHeartbeat()
}
```

## Security Guidance

- Do not embed long-lived org API keys in iOS apps.
- Mint short-lived device tokens from your backend after user/session auth.
- Bind each token to a single organization and minimum required scopes.

## Runtime Auth Manager

```swift
import EdgeML

let auth = DeviceAuthManager(
    baseURL: URL(string: "https://api.edgeml.io")!,
    orgId: "your_org_id",
    deviceIdentifier: "device-123"
)

// Bootstrap with backend-issued bootstrap token
let tokenState = try await auth.bootstrap(
    bootstrapBearerToken: "token_from_your_backend"
)

// Get valid short-lived access token (auto-refreshes when expiring)
let accessToken = try await auth.getAccessToken()
```

## Background Heartbeats

```swift
import BackgroundTasks

class HeartbeatManager {
    static let shared = HeartbeatManager()
    private let client: EdgeMLClient

    func scheduleHeartbeat() {
        let request = BGAppRefreshTaskRequest(identifier: "com.yourapp.heartbeat")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes

        try? BGTaskScheduler.shared.submit(request)
    }

    func handleHeartbeat(task: BGAppRefreshTask) {
        Task {
            try? await client.sendHeartbeat()
            task.setTaskCompleted(success: true)
            scheduleHeartbeat()
        }
    }
}
```

## Requirements

- iOS 13.0+
- Xcode 13.0+
- Swift 5.5+

## Privacy

The SDK collects hardware metadata and runtime constraints for:
- Training eligibility (battery, network)
- Device fleet monitoring
- Model compatibility

All training happens on-device. No personal data or training data is sent to servers.

## License

MIT
