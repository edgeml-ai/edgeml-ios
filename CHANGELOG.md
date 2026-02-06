# Changelog

## 1.1.0 - 2026-02-06
- Added `DeviceAuthManager` with Keychain-backed token storage.
- Added short-lived device token lifecycle support: bootstrap, refresh, revoke.
- Replaced placeholder reachability with `NWPathMonitor` network detection.
- Fixed compile issue in `DeviceInfo` reachability construction.
- Updated docs to use backend-issued short-lived device tokens.
