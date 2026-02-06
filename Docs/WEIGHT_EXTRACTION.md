# CoreML Weight Extraction for Federated Learning

This guide explains how to extract model weights and deltas from CoreML models for federated learning.

## The Challenge

CoreML doesn't natively expose model weights for most models. The CoreML runtime is optimized for inference and on-device training, but weight extraction requires special model preparation.

## Solution Approaches

### 1. **Updatable CoreML Models** (Recommended)

Create models with updatable parameters using Create ML or coremltools:

```python
import coremltools as ct
from coremltools.models.neural_network import NeuralNetworkBuilder

# When converting PyTorch/TensorFlow to CoreML, mark layers as updatable
model = ct.convert(
    pytorch_model,
    inputs=[ct.TensorType(shape=(1, 3, 224, 224))],
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS15,
)

# Make specific layers updatable
spec = model.get_spec()
builder = NeuralNetworkBuilder(spec=spec)

# Mark dense layers as updatable
builder.make_updatable(['dense_1', 'dense_2'])

# Set training inputs
builder.set_training_input([
    ('input', 'Float32', (1, 3, 224, 224)),
    ('target', 'Float32', (1, 10))
])

# Save
model.save('MyModel.mlmodel')
```

### 2. **PyTorch State Dict Serialization**

For models that don't expose parameters, the SDK serializes the entire trained model and lets the server compute deltas:

```swift
// Training returns full weights if delta extraction isn't supported
let weightUpdate = try await trainer.extractWeightUpdate(
    model: model,
    trainingResult: result
)

// weightUpdate.weightsData contains either:
// - Delta (updated - original) if extraction succeeded
// - Full weights if delta extraction not supported
```

### 3. **Custom Weight Extraction**

For advanced use cases, extend `WeightExtractor`:

```swift
class CustomWeightExtractor: WeightExtractor {
    override func extractWeights(from modelURL: URL) async throws -> [String: MLMultiArray] {
        // Custom implementation using your model's structure
        // Access model parameters through CoreML APIs
        let model = try MLModel(contentsOf: modelURL)

        // Extract parameters based on your model architecture
        var weights: [String: MLMultiArray] = [:]
        // ... extraction logic ...

        return weights
    }
}
```

## Serialization Format

The SDK serializes weights to a PyTorch-compatible format:

```
Header:
  - Magic number: 0x50545448 ("PTTH")
  - Version: 1
  - Parameter count: uint32

For each parameter:
  - Name length: uint32
  - Name: UTF-8 string
  - Shape count: uint32
  - Shape dimensions: uint32[]
  - Data type: uint32 (0=float32, 1=float64, 2=int32)
  - Data length: uint32
  - Data: raw bytes
```

Server-side deserialization:

```python
import struct
import torch

def deserialize_ios_weights(data: bytes) -> dict:
    """Deserialize weights from iOS SDK format."""
    offset = 0

    # Read header
    magic, version, param_count = struct.unpack('>III', data[offset:offset+12])
    offset += 12

    if magic != 0x50545448:
        raise ValueError("Invalid magic number")

    weights = {}
    for _ in range(param_count):
        # Read parameter name
        name_len, = struct.unpack('>I', data[offset:offset+4])
        offset += 4
        name = data[offset:offset+name_len].decode('utf-8')
        offset += name_len

        # Read shape
        shape_count, = struct.unpack('>I', data[offset:offset+4])
        offset += 4
        shape = struct.unpack(f'>{shape_count}I', data[offset:offset+shape_count*4])
        offset += shape_count * 4

        # Read data type
        dtype, = struct.unpack('>I', data[offset:offset+4])
        offset += 4

        # Read data
        data_len, = struct.unpack('>I', data[offset:offset+4])
        offset += 4
        tensor_data = data[offset:offset+data_len]
        offset += data_len

        # Convert to torch tensor
        import numpy as np
        array = np.frombuffer(tensor_data, dtype=np.float32)
        tensor = torch.from_numpy(array).reshape(shape)
        weights[name] = tensor

    return weights
```

## Best Practices

### 1. Model Preparation

- Use `mlprogram` format (iOS 15+) instead of `neuralnetwork`
- Explicitly mark layers as updatable during conversion
- Test weight extraction before deploying to devices

### 2. Efficient Training

- Use small batch sizes (8-32) for on-device training
- Limit epochs (1-3) to reduce battery drain
- Extract deltas immediately after training

### 3. Bandwidth Optimization

- Deltas are ~10-50% the size of full weights
- Apply quantization (float32 → float16) for 50% size reduction
- Use compression (zlib) for additional 30-40% reduction

```swift
// Enable compression in EdgeMLConfiguration
let config = EdgeMLConfiguration(
    enableCompression: true,  // Compress weight updates
    compressionLevel: 6       // Balance speed vs size
)
```

### 4. Error Handling

Always handle weight extraction failures gracefully:

```swift
do {
    let update = try await trainer.extractWeightUpdate(
        model: model,
        trainingResult: result
    )
    try await client.uploadWeights(update)
} catch EdgeMLError.weightExtractionFailed(let reason) {
    // Log failure, retry with different approach
    logger.error("Weight extraction failed: \(reason)")

    // Optionally: upload metrics without weights
    try await client.uploadMetrics(trainingResult)
}
```

## Troubleshooting

### "Weight extraction not yet implemented"

**Cause**: Model doesn't expose updatable parameters.

**Solution**: Convert your model with updatable parameters:

```python
import coremltools as ct

# Mark all dense/conv layers as updatable
model = ct.convert(
    pytorch_model,
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS15,
)

spec = model.get_spec()
for layer in spec.neuralNetwork.layers:
    if layer.WhichOneof('layer') in ['innerProduct', 'convolution']:
        layer.isUpdatable = True

model.save('model.mlmodel')
```

### "Parameter extraction not supported"

**Cause**: CoreML model format doesn't expose weights.

**Fallback**: SDK automatically falls back to full weight serialization.

### Large Upload Sizes

**Problem**: Full weights are too large for cellular upload.

**Solutions**:
1. Use delta extraction (requires updatable models)
2. Enable compression in configuration
3. Wait for Wi-Fi using `BackgroundConstraints`

```swift
let constraints = BackgroundConstraints(
    requiresWiFi: true,
    requiresCharging: false,
    minimumBatteryLevel: 0.3
)
```

## Testing Weight Extraction

Test your model's weight extraction capability:

```swift
let extractor = WeightExtractor()

do {
    // Test delta extraction
    let delta = try await extractor.extractWeightDelta(
        originalModelURL: originalURL,
        updatedContext: trainingContext
    )
    print("✅ Delta extraction works: \(delta.count) bytes")
} catch {
    print("⚠️ Delta extraction failed: \(error)")

    // Test full weight extraction
    do {
        let weights = try await extractor.extractFullWeights(
            updatedContext: trainingContext
        )
        print("✅ Full weight extraction works: \(weights.count) bytes")
    } catch {
        print("❌ Weight extraction not supported")
    }
}
```

## References

- [CoreML Updatable Models](https://developer.apple.com/documentation/coreml/updating_a_model_with_on-device_training)
- [coremltools Documentation](https://coremltools.readme.io/)
- [PyTorch to CoreML Conversion](https://pytorch.org/mobile/ios/#core-ml)
- [EdgeML Federated Learning Guide](../docs/FEDERATED_LEARNING.md)
