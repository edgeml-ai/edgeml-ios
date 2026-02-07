# EdgeML iOS SDK

Swift SDK for privacy-safe on-device personalization and federated learning.

## Enterprise Runtime Auth (required)

Do not embed org API keys in shipped apps. Use backend-issued bootstrap tokens and short-lived device credentials.

**Server endpoints**
- `POST /api/v1/device-auth/bootstrap`
- `POST /api/v1/device-auth/refresh`
- `POST /api/v1/device-auth/revoke`

**Default lifetimes**
- Access token: 15 minutes (configurable, max 60 minutes)
- Refresh token: 30 days (rotated on refresh)

## Installation

```swift
dependencies: [
  .package(url: "https://github.com/edgeml-ai/edgeml-ios", from: "0.1.0")
]
```

## Quick Start (Enterprise)

### 1) Bootstrap short-lived device auth

```swift
import EdgeML

let auth = DeviceAuthManager(
  baseURL: URL(string: "https://api.edgeml.io")!,
  orgId: "org_123",
  deviceIdentifier: "ios-device-abc"
)

let tokenState = try await auth.bootstrap(
  bootstrapBearerToken: backendBootstrapToken
)
let accessToken = try await auth.getAccessToken()
```

### 2) Initialize EdgeML client

```swift
let client = EdgeMLClient(
  deviceAccessToken: accessToken,
  orgId: "org_123",
  serverURL: URL(string: "https://api.edgeml.io")!,
  configuration: .production
)
```

### 3) Register and run

```swift
let registration = try await client.register(metadata: ["app_version": "1.0.0"])
let model = try await client.downloadModel(modelId: "ad-relevance")
```

## Token lifecycle

- Call `getAccessToken()` before network calls.
- SDK refreshes near expiry via refresh token.
- On logout/device compromise, revoke session and clear local secure state.

## Secure storage

Token state is stored in iOS Keychain.

## Core capabilities

- device registration and heartbeat
- model download/cache
- on-device inference
- local training + update upload
- background sync scheduling

## Docs

- https://docs.edgeml.io/sdks/ios
- https://docs.edgeml.io/reference/api-endpoints
