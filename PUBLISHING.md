# Publishing the Octomil iOS SDK

This guide explains how to publish the Octomil iOS SDK for distribution.

## Quick Links

- **PR**: https://github.com/sbangalore/fed-learning/pull/new/feat/ios-weight-extraction
- **Docs**: `octomil-ios/Docs/WEIGHT_EXTRACTION.md`

## Changes Summary

✅ **Implemented**: CoreML weight/delta extraction for federated learning
✅ **New File**: `WeightExtractor.swift` - Production-ready weight extraction
✅ **Updated**: `FederatedTrainer.swift` - Automatic delta vs full weight detection
✅ **Documented**: Complete guide with code samples and troubleshooting

## Distribution Options

### 1. Swift Package Manager (Recommended for Beta)

Swift Package Manager is the easiest way to distribute the SDK to developers.

#### Step 1: Tag a Release

```bash
# Version the release
git tag -a v1.1.0 -m "Add CoreML weight extraction for federated learning

New features:
- Weight delta extraction (updated - original)
- Full weight fallback for unsupported models
- PyTorch-compatible serialization
- Comprehensive documentation
"

# Push tag
git push origin v1.1.0
```

#### Step 2: Create GitHub Release

1. Go to https://github.com/sbangalore/fed-learning/releases/new
2. Choose tag: `v1.1.0`
3. Release title: "Octomil iOS SDK v1.1.0 - Weight Extraction"
4. Description:
```markdown
## Octomil iOS SDK v1.1.0

### New Features
- ✨ CoreML weight/delta extraction for federated learning
- 🔄 Automatic fallback from delta to full weights
- 📦 PyTorch-compatible serialization format
- 📚 Comprehensive documentation and examples

### Installation

**Swift Package Manager:**
```swift
dependencies: [
    .package(url: "https://github.com/sbangalore/fed-learning.git", from: "1.1.0")
]
```

**Usage:**
```swift
let result = try await trainer.train(model: model, dataProvider: { data }, config: config)
let update = try await trainer.extractWeightUpdate(model: model, trainingResult: result)
try await client.uploadWeights(update)
```

### Documentation
- [Weight Extraction Guide](octomil-ios/Docs/WEIGHT_EXTRACTION.md)
- [API Documentation](#)

### Breaking Changes
None - fully backward compatible

### Requirements
- iOS 15.0+ / macOS 12.0+
- Swift 5.7+
- Xcode 14+
```

5. Attach binaries (optional): Build XCFramework (see below)
6. Publish release

#### Step 3: Developers Install

Developers add to their `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/sbangalore/fed-learning.git",
        from: "1.1.0"
    )
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "Octomil", package: "fed-learning")
        ]
    )
]
```

Or in Xcode:
1. File → Add Packages
2. Enter repository URL: `https://github.com/sbangalore/fed-learning`
3. Select version: `1.1.0`
4. Add to target

---

### 2. CocoaPods (For Legacy Projects)

#### Step 1: Create Podspec

Create `Octomil.podspec` in repo root:

```ruby
Pod::Spec.new do |s|
  s.name             = 'Octomil'
  s.version          = '1.1.0'
  s.summary          = 'Federated learning SDK for iOS'
  s.description      = <<-DESC
    Octomil enables on-device federated learning with CoreML models.
    Features weight extraction, delta computation, and automatic aggregation.
  DESC

  s.homepage         = 'https://github.com/sbangalore/fed-learning'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Octomil' => 'team@octomil.com' }
  s.source           = {
    :git => 'https://github.com/sbangalore/fed-learning.git',
    :tag => s.version.to_s
  }

  s.ios.deployment_target = '15.0'
  s.swift_version = '5.7'

  s.source_files = 'octomil-ios/Sources/Octomil/**/*.swift'
  s.resources = 'octomil-ios/Sources/Octomil/**/*.{xcassets,strings}'

  s.frameworks = 'Foundation', 'CoreML', 'Combine'
end
```

#### Step 2: Validate and Publish

```bash
# Validate
pod lib lint Octomil.podspec

# Register (first time only)
pod trunk register team@octomil.com 'Octomil Team'

# Publish
pod trunk push Octomil.podspec
```

#### Step 3: Developers Install

Add to `Podfile`:

```ruby
pod 'Octomil', '~> 1.1'
```

---

### 3. XCFramework (For Manual Distribution)

Build a universal binary for manual integration.

#### Step 1: Build XCFramework

```bash
cd octomil-ios

# Clean
rm -rf build/
rm -f Octomil.xcframework.zip

# Build for iOS devices
xcodebuild archive \
  -scheme Octomil \
  -destination "generic/platform=iOS" \
  -archivePath "build/ios" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Build for iOS Simulator
xcodebuild archive \
  -scheme Octomil \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "build/ios-simulator" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Build for macOS (if supported)
xcodebuild archive \
  -scheme Octomil \
  -destination "generic/platform=macOS" \
  -archivePath "build/macos" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Create XCFramework
xcodebuild -create-xcframework \
  -framework build/ios.xcarchive/Products/Library/Frameworks/Octomil.framework \
  -framework build/ios-simulator.xcarchive/Products/Library/Frameworks/Octomil.framework \
  -framework build/macos.xcarchive/Products/Library/Frameworks/Octomil.framework \
  -output Octomil.xcframework

# Zip for distribution
zip -r Octomil.xcframework.zip Octomil.xcframework

# Generate checksum
shasum -a 256 Octomil.xcframework.zip
```

#### Step 2: Attach to GitHub Release

1. Upload `Octomil.xcframework.zip` to GitHub release
2. Add checksum to release notes:
```markdown
### Manual Installation

Download [Octomil.xcframework.zip](link-to-release)

**Checksum (SHA-256):**
```
abc123...xyz789
```

**Installation:**
1. Download and unzip
2. Drag Octomil.xcframework into Xcode project
3. Embed & Sign in target settings
```

---

### 4. TestFlight (For Testing Apps Using SDK)

If you have a demo app that uses the SDK:

#### Step 1: Create Xcode Cloud Workflow

1. Xcode → Product → Xcode Cloud → Create Workflow
2. Select "Octomil Demo" app target
3. Configure:
   - **Trigger**: On tag push matching `demo/v*`
   - **Actions**: Archive for TestFlight
   - **Post-Actions**: Notify TestFlight beta testers

#### Step 2: Tag Demo Release

```bash
# Tag demo app version
git tag -a demo/v1.0.1 -m "Demo app with weight extraction v1.1.0"
git push origin demo/v1.0.1
```

#### Step 3: TestFlight Distribution

1. Xcode Cloud automatically builds and uploads
2. Go to App Store Connect → TestFlight
3. Add internal testers
4. (Optional) Submit for beta review for external testers

---

## Publishing Checklist

### Pre-Release
- [ ] All tests pass: `swift test`
- [ ] Example app builds successfully
- [ ] Documentation is up to date
- [ ] CHANGELOG.md updated
- [ ] Version bumped in:
  - [ ] Package.swift
  - [ ] Octomil.podspec (if using CocoaPods)
  - [ ] Info.plist (if applicable)

### Release
- [ ] Create and push git tag: `git tag -a v1.1.0`
- [ ] Create GitHub release with notes
- [ ] Publish to CocoaPods (if using): `pod trunk push`
- [ ] Update documentation website
- [ ] Announce in release notes / blog

### Post-Release
- [ ] Monitor GitHub issues for bug reports
- [ ] Update demo apps to use new version
- [ ] Create migration guide if breaking changes
- [ ] Update integration tests

---

## Version Numbering

Follow Semantic Versioning (semver):

- **Major (1.x.x)**: Breaking changes
- **Minor (x.1.x)**: New features, backward compatible
- **Patch (x.x.1)**: Bug fixes, backward compatible

**This release: 1.1.0** (new feature, no breaking changes)

---

## Testing the Release

Before publishing, test installation:

### Test SPM Installation

```bash
# Create test project
mkdir test-spm && cd test-spm
swift package init --type executable

# Add dependency
cat > Package.swift << EOF
// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "test-spm",
    platforms: [.iOS(.v15), .macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/sbangalore/fed-learning.git", branch: "feat/ios-weight-extraction")
    ],
    targets: [
        .executableTarget(
            name: "test-spm",
            dependencies: [
                .product(name: "Octomil", package: "fed-learning")
            ]
        )
    ]
)
EOF

# Build
swift build
```

### Test XCFramework Installation

```bash
# Unzip
unzip Octomil.xcframework.zip

# Create test Xcode project
open -a Xcode

# Drag Octomil.xcframework into project
# Build and verify no errors
```

---

## Rollback Procedure

If the release has critical bugs:

### Unpublish from CocoaPods

```bash
# Deprecate version
pod trunk deprecate Octomil 1.1.0 \
  --in-favor-of=1.0.9 \
  --message="Critical bug, use 1.0.9 instead"
```

### Remove GitHub Release

1. GitHub → Releases → Edit v1.1.0
2. Mark as "Pre-release" or delete
3. Create hotfix release v1.1.1

### Notify Users

- Post GitHub issue explaining the problem
- Update documentation with migration guide
- Send notification to registered developers

---

## Support Resources

After publishing:

1. **Documentation**: Keep docs/ up to date
2. **Examples**: Update demo apps with new features
3. **Support**: Monitor GitHub issues and discussions
4. **Analytics**: Track adoption with package metrics

---

## Next Steps

After this release (v1.1.0), consider:

1. **Performance optimizations**:
   - Implement compression for weight updates
   - Add quantization (float32 → float16)
   - Optimize serialization format

2. **Advanced features**:
   - Sparse weight updates
   - Differential privacy
   - Secure aggregation

3. **Developer experience**:
   - SwiftUI view modifiers for training UI
   - Combine publishers for training progress
   - Async/await throughout API

4. **Documentation**:
   - Video tutorials
   - Interactive playground
   - Best practices guide

---

## Questions?

- **Issues**: https://github.com/sbangalore/fed-learning/issues
- **Discussions**: https://github.com/sbangalore/fed-learning/discussions
- **Email**: team@octomil.com (if applicable)
