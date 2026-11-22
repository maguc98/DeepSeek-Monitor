# DeepSeek Monitor

A native iOS dashboard for viewing DeepSeek Open Platform account and usage data.

## Approved UI direction

The initial SwiftUI implementation follows the approved eight-screen reference: welcome, embedded sign-in, overview, usage analytics, model analytics, request records, request detail, and settings. The visual system uses a soft lavender canvas, blue-to-purple primary gradient, white rounded cards, restrained shadows, and a five-item bottom navigation bar.

## Current implementation

- [x] SwiftUI app entry point and five-tab navigation
- [x] Welcome page and embedded DeepSeek Platform web sign-in
- [x] Overview, analytics, models, records, record-detail, and settings screens
- [x] Empty and unavailable states instead of fabricated account metrics
- [x] Embedded WKWebView console adapter for account summary and usage buckets
- [x] Current-day hourly buckets plus rolling 30-day daily buckets
- [x] Shared data models for dashboard, trend chart, and model breakdown
- [x] XcodeGen project definition and iOS Simulator build workflow
- [ ] Validate token storage and private console routes with a real signed-in account on device
- [ ] Persist timestamped observations with SwiftData
- [x] Connect verified daily/hourly aggregate data to charts and model usage
- [ ] Identify a supported per-request history source before implementing real request records
- [ ] Add refresh scheduling, cache lifecycle, and notifications

## Build

On macOS with Xcode installed:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project DeepSeekMonitor.xcodeproj -scheme DeepSeekMonitor -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Data-source and security rules

- Never collect or transmit account passwords.
- Never upload cookies, session tokens, or API keys to a third-party server.
- Keep session material on device and restrict it to the minimum required.
- Respect login challenges, expiry, and platform access controls.
- Do not assume WKWebView cookies can be freely shared with arbitrary networking clients; validate the supported session flow.
- Clearly label stale cached data and last synchronization time.
- Treat undocumented console endpoints as unstable and isolate them behind adapters.
- Show unavailable metrics as unavailable; never display guessed values as official platform data.
