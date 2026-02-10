# EdgeML iOS SDK

[![CI](https://github.com/edgeml-ai/edgeml-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/edgeml-ai/edgeml-ios/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/edgeml-ai/edgeml-ios/branch/main/graph/badge.svg)](https://codecov.io/gh/edgeml-ai/edgeml-ios)
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=edgeml-ai_edgeml-ios&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=edgeml-ai_edgeml-ios)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=edgeml-ai_edgeml-ios&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=edgeml-ai_edgeml-ios)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/edgeml-ai/edgeml-ios/badge)](https://scorecard.dev/viewer/?uri=github.com/edgeml-ai/edgeml-ios)
[![CodeQL](https://github.com/edgeml-ai/edgeml-ios/actions/workflows/codeql.yml/badge.svg)](https://github.com/edgeml-ai/edgeml-ios/actions/workflows/codeql.yml)
[![CII Best Practices](https://www.bestpractices.dev/projects/11913/badge)](https://www.bestpractices.dev/projects/11913)
[![Swift Version](https://img.shields.io/badge/Swift-5.5%2B-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-iOS%2013.0%2B-lightgrey.svg)](https://github.com/edgeml-ai/edgeml-ios)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> Enterprise-grade iOS SDK for privacy-preserving federated learning on Apple devices.

## Overview

The EdgeML iOS SDK brings production-ready federated learning to iPhone and iPad. Designed with Apple's privacy principles in mind, it enables on-device training while maintaining complete data sovereignty.

### Key Features

- **Privacy-First**: All training happens on-device, data never leaves the phone
- **Secure Aggregation**: SecAgg+ protocol with Shamir secret sharing -- raw gradients never leave the device
- **CoreML Optimized**: Leverages Neural Engine for on-device training
- **Streaming Inference**: Multi-modal (text, image, audio, video) with automatic TTFC/throughput metrics
- **On-Device Personalization**: Incremental learning with local-only and federated modes
- **Production Ready**: Complete hardware metadata and runtime constraint monitoring
- **Battery Aware**: Training eligibility based on battery level and charging state
- **Network Smart**: Respects WiFi-only preferences for model sync
- **Type Safe**: 100% Swift with comprehensive type safety, zero external dependencies

### Security & Privacy

- ✅ **Code Coverage**: >80% test coverage
- ✅ **Static Analysis**: SonarCloud quality gates enforced
- ✅ **Security Scanning**: SwiftLint checks on every commit
- ✅ **Data Privacy**: Training data never leaves device
- ✅ **Stable IDs**: IDFV (Identifier For Vendor) based device IDs

## Requirements

- iOS 13.0+ / iPadOS 13.0+
- Xcode 13.0+
- Swift 5.5+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/edgeml-ai/edgeml-ios.git", from: "1.0.0")
]
```

### CocoaPods

```ruby
pod 'EdgeML', '~> 1.0'
```

## Quick Start

### Basic Device Registration

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

### Full Integration Example

```swift
import Foundation
import EdgeML

class EdgeMLClient {
    private let baseURL: String
    private let apiKey: String
    private let device = DeviceInfo()
    private var deviceServerId: String?

    init(apiKey: String, baseURL: String = "https://api.edgeml.io") {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    func register(orgId: String) async throws -> String {
        var data = device.toRegistrationDict()
        data["org_id"] = orgId
        data["sdk_version"] = "1.0.0"

        let url = URL(string: "\(baseURL)/api/v1/devices/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["metadata": metadata])

        let _ = try await URLSession.shared.data(for: request)
    }
}

// Usage
let client = EdgeMLClient(apiKey: "edg_your_key_here")
Task {
    let deviceId = try await client.register(orgId: "your_org_id")
    print("Registered with ID: \(deviceId)")

    // Send periodic heartbeats
    try await client.sendHeartbeat()
}
```

## Device Information Collected

### Hardware Metadata
- **Manufacturer**: "Apple"
- **Model**: Device model code (e.g., "iPhone15,2")
- **CPU Architecture**: "arm64"
- **Total Memory**: Available RAM in MB
- **Available Storage**: Free disk space in MB
- **Neural Engine**: Availability status

### Runtime Constraints
- **Battery Level**: 0-100%
- **Charging State**: Plugged in or running on battery
- **Network Type**: WiFi, cellular, or offline

### System Information
- **Platform**: "ios"
- **OS Version**: iOS/iPadOS version
- **Locale**: User's language and region
- **Timezone**: Device timezone

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

### Info.plist Configuration

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.yourapp.heartbeat</string>
</array>

<key>NSUserTrackingUsageDescription</key>
<string>We use federated learning to improve model performance while keeping your data private</string>
```

## Best Practices

### Security

1. **Use HTTPS Only**: Never send credentials over HTTP
2. **Secure Storage**: Store API keys in Keychain, not UserDefaults
3. **Certificate Pinning**: Enable SSL pinning for production
4. **Background Tasks**: Use `BGTaskScheduler` for periodic updates

### Performance

1. **Battery Awareness**: Only train when battery > 20% and charging
2. **WiFi Preference**: Default to WiFi-only for model downloads
3. **CoreML Acceleration**: Leverage Neural Engine when available
4. **Memory Management**: Monitor memory usage during training

### Privacy

1. **Differential Privacy**: Enable noise injection for gradient updates
2. **Federated Analytics**: Use aggregated metrics only
3. **User Consent**: Request explicit consent for federated learning
4. **Data Minimization**: Send only model gradients, never raw data

## Testing

```bash
# Run all tests
swift test

# Run with coverage
swift test --enable-code-coverage

# Generate coverage report
xcrun llvm-cov show .build/debug/EdgeMLPackageTests.xctest/Contents/MacOS/EdgeMLPackageTests \
    -instr-profile .build/debug/codecov/default.profdata
```

## Documentation

For full SDK documentation, see [https://docs.edgeml.io/sdks/ios](https://docs.edgeml.io/sdks/ios)

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
# Clone repository
git clone https://github.com/edgeml-ai/edgeml-ios.git
cd edgeml-ios

# Open in Xcode
open Package.swift

# Or build from command line
swift build
swift test
```

## Privacy Statement

### Data Collection Disclosure

The SDK automatically collects the following device information:

**Hardware Metadata** (collected once at registration):
- Device manufacturer, model, and CPU architecture
- Total RAM and available storage
- Neural Engine availability
- iOS/iPadOS version
- Locale and timezone

**Runtime Constraints** (collected periodically via heartbeats):
- **Battery Level** (0-100%): Read using `UIDevice.batteryLevel` API
- **Charging State**: Whether device is plugged in
- **Network Type**: WiFi, cellular, or offline status

### No User Permissions Required

The SDK uses iOS system APIs that **do not trigger permission prompts**:
- `UIDevice.batteryLevel` - reads battery percentage silently
- `CTTelephonyNetworkInfo` - detects network type
- Standard device info APIs

Users are **not** asked for any permissions to enable this data collection.

### Why This Data is Collected

- **Training Eligibility**: Ensures training only happens when battery/network conditions are suitable
- **Fleet Monitoring**: Helps understand device distribution and health across your user base
- **Model Compatibility**: Ensures models fit within device hardware capabilities

### App Store Privacy Disclosure

**You must disclose this data collection in your App Store privacy nutrition label:**
- Under "Device ID" → Include device identifiers (IDFV)
- Under "Other Diagnostic Data" → Include battery level, network type, device specs
- Mark usage as "Analytics" or "App Functionality"

### What Data is NOT Collected

**Important**: All training happens **on-device**. The SDK never collects or transmits:
- ❌ Personal information or user data
- ❌ Training datasets or raw input data
- ❌ Location data
- ❌ Contacts, photos, or files
- ❌ User behavior or app usage patterns

Only aggregated model gradients (mathematical weight updates) are uploaded to the server.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues and feature requests, please use the [GitHub issue tracker](https://github.com/edgeml-ai/edgeml-ios/issues).

For questions: support@edgeml.io

---

<p align="center">
  <strong>Built with ❤️ by the EdgeML Team</strong>
</p>
