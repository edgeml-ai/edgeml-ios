# On-Device Personalization for iOS

This guide explains how to implement continuous on-device personalization with the EdgeML iOS SDK, enabling adaptive learning similar to Google Keyboard.

## Overview

Personalization allows your app to incrementally improve its ML model based on user interactions, all while keeping data local and private. The model adapts to individual user patterns without sending raw data to servers.

## Key Features

- **Incremental Training**: Update the model with new data as it arrives
- **Background Processing**: Train automatically when conditions are met
- **Privacy-First**: All training happens on-device, no raw data leaves the device
- **Smart Buffering**: Collect samples and trigger training at optimal times
- **Model Versioning**: Maintain personalized versions per user
- **Automatic Uploads**: Periodically share aggregated updates with the server

## Quick Start

### 1. Initialize Personalization Manager

```swift
import EdgeML

// Create configuration
let config = EdgeMLConfiguration(
    apiKey: "your-api-key",
    serverURL: URL(string: "https://api.edgeml.ai")!,
    enableLogging: true
)

// Create client and trainer
let client = EdgeMLClient(configuration: config)
let trainer = FederatedTrainer(configuration: config)

// Create personalization manager
let personalization = PersonalizationManager(
    configuration: config,
    trainer: trainer,
    bufferSize: 50,           // Trigger training after 50 samples
    minSamples: 10,            // Minimum samples to start training
    trainingInterval: 300,     // Wait 5 minutes between sessions
    autoUpload: true,          // Auto-upload updates
    uploadThreshold: 10        // Upload after 10 training sessions
)

// Set base model
let model = try await client.downloadModel(modelId: "my-model", version: "1.0.0")
await personalization.setBaseModel(model)
```

### 2. Collect Training Data

As users interact with your app, collect training samples:

```swift
// Example: Text prediction app
func userAcceptedSuggestion(input: String, accepted: String) async {
    // Convert to ML features
    let inputFeatures = createInputFeatures(from: input)
    let targetFeatures = createTargetFeatures(from: accepted)

    // Add to personalization buffer
    try? await personalization.addTrainingSample(
        input: inputFeatures,
        target: targetFeatures,
        metadata: [
            "type": "suggestion_accepted",
            "context": "keyboard"
        ]
    )
}

// Example: Image classification app
func userCorrectedPrediction(image: UIImage, correctLabel: String) async {
    let inputFeatures = extractImageFeatures(from: image)
    let targetFeatures = createLabelFeatures(from: correctLabel)

    try? await personalization.addTrainingSample(
        input: inputFeatures,
        target: targetFeatures,
        metadata: ["type": "correction"]
    )
}
```

### 3. Use Personalized Model

```swift
// Get the current model (personalized if available, base otherwise)
if let currentModel = await personalization.getCurrentModel() {
    // Use for inference
    let prediction = try await model.predict(input: inputData)
}
```

### 4. Monitor Progress

```swift
// Get personalization statistics
let stats = await personalization.getStatistics()

print("Training Sessions: \(stats.totalTrainingSessions)")
print("Samples Trained: \(stats.totalSamplesTrained)")
print("Buffered Samples: \(stats.bufferedSamples)")
print("Average Loss: \(stats.averageLoss ?? 0)")
print("Is Personalized: \(stats.isPersonalized)")

// Get training history
let history = await personalization.getTrainingHistory()
for session in history {
    print("Session at \(session.timestamp): \(session.sampleCount) samples")
}
```

## Real-World Examples

### Example 1: Smart Keyboard

```swift
class KeyboardMLManager {
    private let personalization: PersonalizationManager
    private let model: EdgeMLModel

    func userTyped(_ text: String) async {
        // Extract context (previous words)
        let context = getRecentContext()

        // Get next word predictions
        let predictions = try? await predictNextWord(context: context)

        // Show predictions to user
        showPredictions(predictions)
    }

    func userAcceptedPrediction(_ prediction: String) async {
        // Learn from this interaction
        let context = getRecentContext()

        let inputFeatures = createFeatures(context: context)
        let targetFeatures = createFeatures(word: prediction)

        try? await personalization.addTrainingSample(
            input: inputFeatures,
            target: targetFeatures,
            metadata: ["accepted": true]
        )
    }

    func userIgnoredPredictions() async {
        // Could optionally learn from rejections too
        // This helps the model understand user preferences
    }
}
```

### Example 2: Photo Auto-Tag

```swift
class PhotoTaggingManager {
    private let personalization: PersonalizationManager

    func userViewedPhoto(_ photo: Photo) async {
        // Get model predictions
        let predictions = try? await predict(photo: photo)

        // Show suggested tags
        showSuggestedTags(predictions)
    }

    func userConfirmedTag(_ photo: Photo, tag: String) async {
        // User confirmed/corrected a tag - learn from this
        let imageFeatures = extractFeatures(from: photo.image)
        let tagFeatures = createTagFeatures(from: tag)

        try? await personalization.addTrainingSample(
            input: imageFeatures,
            target: tagFeatures,
            metadata: [
                "photo_id": photo.id,
                "confirmed": true
            ]
        )
    }
}
```

### Example 3: Email Smart Reply

```swift
class SmartReplyManager {
    private let personalization: PersonalizationManager

    func generateReplies(for email: Email) async -> [String] {
        // Use personalized model to generate replies
        let context = extractEmailContext(email)
        let replies = try? await model.generateReplies(context: context)
        return replies ?? []
    }

    func userSelectedReply(_ reply: String, for email: Email) async {
        // Learn from user's choice
        let emailFeatures = extractEmailContext(email)
        let replyFeatures = createReplyFeatures(from: reply)

        try? await personalization.addTrainingSample(
            input: emailFeatures,
            target: replyFeatures,
            metadata: ["email_type": email.category]
        )
    }
}
```

## Advanced Configuration

### Custom Training Triggers

```swift
// Manual training control
class CustomPersonalizationManager {
    private let personalization: PersonalizationManager

    func trainWhenIdle() async {
        // Check if device is idle
        guard isDeviceIdle() else { return }

        // Force training
        try? await personalization.forceTraining()
    }

    func trainOnWiFi() async {
        // Check network status
        guard isConnectedToWiFi() else { return }

        try? await personalization.forceTraining()
    }
}
```

### Buffer Management

```swift
// Clear buffer without training (e.g., if user opts out)
await personalization.clearBuffer()

// Reset all personalization (e.g., user requests)
try await personalization.resetPersonalization()
```

### Privacy Controls

```swift
// Let users control personalization
class PrivacySettings {
    func disablePersonalization() async {
        // Clear buffer
        await personalization.clearBuffer()

        // Reset to base model
        try? await personalization.resetPersonalization()
    }

    func exportPersonalizationData() async -> PersonalizationStatistics {
        // Let users see what data is used for personalization
        return await personalization.getStatistics()
    }
}
```

## Best Practices

### 1. Buffer Size Tuning

- **Small buffers (10-30)**: Faster adaptation, more frequent training
- **Large buffers (50-100)**: More stable updates, less battery use
- **Very large (100+)**: Batch training, suitable for powerful devices

### 2. Training Frequency

- **Frequent (1-5 min)**: Real-time adaptation (e.g., keyboard)
- **Moderate (5-15 min)**: Balanced approach
- **Infrequent (30-60 min)**: Battery-conscious apps

### 3. Learning Rate

```swift
// For incremental updates, use small learning rates
let config = TrainingConfig(
    epochs: 1,
    batchSize: 32,
    learningRate: 0.0001  // Small = stable personalization
)
```

### 4. Battery Optimization

```swift
// Train only when charging
func shouldAllowTraining() -> Bool {
    UIDevice.current.isBatteryMonitoringEnabled = true

    let batteryLevel = UIDevice.current.batteryLevel
    let batteryState = UIDevice.current.batteryState

    // Only train if charging or battery > 30%
    return batteryState == .charging || batteryLevel > 0.3
}
```

### 5. Storage Management

```swift
// Periodically clean up old personalized models
func cleanupOldModels() async {
    let stats = await personalization.getStatistics()

    // If personalization isn't helping, reset it
    if let accuracy = stats.averageAccuracy, accuracy < baselineAccuracy {
        try? await personalization.resetPersonalization()
    }
}
```

## Privacy Considerations

### What Stays on Device

✅ **Always Local**:
- Raw training data (user inputs, corrections)
- Personalized model weights
- Training buffer contents
- Individual training samples

### What Can Be Uploaded

⚠️ **Only Aggregated Updates**:
- Weight deltas (not raw data)
- Training statistics (counts, averages)
- Model performance metrics

### User Controls

Provide users with:
- Option to disable personalization
- Ability to reset personalized model
- Visibility into training statistics
- Export of personalization data

```swift
// Example settings screen
struct PersonalizationSettingsView: View {
    @State private var personalizationEnabled = true
    @State private var stats: PersonalizationStatistics?

    var body: some View {
        Form {
            Section("Personalization") {
                Toggle("Enable Model Personalization", isOn: $personalizationEnabled)
                    .onChange(of: personalizationEnabled) { enabled in
                        if !enabled {
                            Task {
                                await personalization.clearBuffer()
                            }
                        }
                    }
            }

            Section("Statistics") {
                if let stats = stats {
                    Text("Training Sessions: \(stats.totalTrainingSessions)")
                    Text("Samples: \(stats.totalSamplesTrained)")
                    if stats.isPersonalized {
                        Text("Model: Personalized")
                            .foregroundColor(.green)
                    }
                }
            }

            Section {
                Button("Reset Personalization", role: .destructive) {
                    Task {
                        try? await personalization.resetPersonalization()
                    }
                }
            }
        }
        .task {
            stats = await personalization.getStatistics()
        }
    }
}
```

## Troubleshooting

### Training Not Triggering

**Problem**: Samples are buffered but training doesn't start.

**Check**:
- Buffer size threshold: `stats.bufferedSamples >= bufferSize`
- Minimum samples: `stats.bufferedSamples >= minSamples`
- Training interval: Check `lastTrainingDate`
- Training in progress: Only one session at a time

### Poor Personalization Quality

**Problem**: Model quality degrades with personalization.

**Solutions**:
- Reduce learning rate (try 0.00001)
- Increase buffer size for more stable updates
- Reset personalization if accuracy drops too much
- Validate training data quality

### High Battery Usage

**Problem**: Personalization drains battery.

**Solutions**:
- Increase training interval
- Increase buffer size
- Train only when charging
- Reduce epochs (use 1)

## References

- [CoreML On-Device Training](https://developer.apple.com/documentation/coreml/updating_a_model_with_on-device_training)
- [EdgeML Federated Learning Guide](FEDERATED_LEARNING.md)
- [Privacy Best Practices](PRIVACY.md)
