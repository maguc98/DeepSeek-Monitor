# DeepSeek Monitor

A native iOS dashboard for viewing DeepSeek Open Platform account and usage data.

## Product direction

The app uses an embedded sign-in flow for the DeepSeek Open Platform, then presents the information in a native SwiftUI interface. The platform remains the source of truth: the app should read values that the account console actually exposes rather than fabricate or silently estimate account-wide history.

## Dashboard information architecture

### Overview
- Account balance and balance breakdown, when exposed by the platform
- Usage / spend summary
- Token totals and request totals, when available
- Last successful synchronization time and data-source status

### Platform pages and data mapping
- Keep an explicit registry of the DeepSeek console pages/data sources that the app supports.
- Map each displayed metric to its source page, source field, unit, timestamp, and retrieval time.
- Show unavailable metrics as unavailable; never present guessed values as official platform data.
- Prefer documented public endpoints. Any page-internal endpoint is an implementation detail and may change; isolate it behind an adapter and validate responses.

### Usage analytics
Provide interactive line charts with:
- Time ranges: 24 hours, 7 days, 30 days, and custom range where source data permits
- Metrics: spend, input tokens, output tokens, cached tokens, and request count where available
- Clear units, axis labels, selected-point values, and empty/loading/error states
- Aggregation that preserves source timestamps and avoids double-counting
- A visible distinction between platform-reported history and locally collected observations

### Records
- Recent usage observations and synchronization history
- Detail view with metric, value, unit, source, and timestamp

## Initial technical direction

- SwiftUI for the native interface
- WKWebView for the user-initiated sign-in experience
- Keychain for sensitive session material, subject to platform and security constraints
- A dedicated data-source adapter layer
- SwiftData for locally cached observations and chart history
- Charts framework for native line charts

## Security and reliability

- Do not collect or transmit account passwords.
- Do not upload cookies, session tokens, or API keys to a third-party server.
- Keep session material on device and restrict it to the minimum required.
- Respect login challenges, expiry, and platform access controls.
- Do not assume WKWebView cookies can be freely shared with arbitrary networking clients; validate the supported session flow.
- Clearly label stale cached data and the last synchronization time.
- Treat undocumented console endpoints as unstable and provide graceful failure when they change.

## First implementation milestones

1. Establish the SwiftUI app shell and navigation.
2. Implement embedded sign-in and session lifecycle handling.
3. Inventory the values and pages visible in the signed-in DeepSeek console.
4. Implement source adapters and typed metric models.
5. Persist timestamped observations.
6. Build interactive line charts and range selectors.
7. Add refresh, stale-data, sign-out, and error states.

The repository intentionally starts with product documentation. App implementation will follow in focused, reviewable commits.
