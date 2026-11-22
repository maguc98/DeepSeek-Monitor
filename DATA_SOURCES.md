# DeepSeek data-source inventory

Checked against the public DeepSeek API documentation and public community implementations on 2026-11-23.

## Source classes

| Data | Route / method | Authentication | Classification | App handling |
|---|---|---|---|---|
| Current balance | GET https://api.deepseek.com/user/balance | API Key Bearer | Official documented API | Schema documented; optional API-key route, not required for the embedded-session prototype |
| Available models | GET https://api.deepseek.com/models | API Key Bearer | Official documented API | Model catalogue only; not usage history |
| Account summary | GET /api/v0/users/get_user_summary on platform.deepseek.com | Platform web-session token | Undocumented internal console route | Isolated in DeepSeekPlatformSession; defensive parsing and graceful errors |
| Daily token/request usage | GET /api/v0/usage/by_api_key/amount?start=&end=&tz= | Platform web-session token | Undocumented internal console route | Daily/model aggregate data only |
| Daily cost | GET /api/v0/usage/by_api_key/cost?start=&end=&tz= | Platform web-session token | Undocumented internal console route | Daily/model aggregate data only |
| Per-request detail history | No verified route | Unknown | Not verified | Keep request list/detail empty until a supported source is identified |

## Session handling

The prototype reuses the user's embedded WKWebView session. For console requests, JavaScript executes within the platform.deepseek.com page context, reads only known local-storage token names (userToken, token, authToken, accessToken) in memory, and sends a same-origin request with a Bearer header. The token is never returned to Swift, printed, copied to an external service, or saved separately by the app. Passwords are never read.

The console endpoints are private implementation details, not a public API contract. DeepSeek can change them, their payload shape, authentication, time-zone rules, or rate limits at any time. They must remain isolated and disposable. HTTP errors, session expiry, and schema mismatches must be shown as unavailable instead of being converted into zeros.

## Verified response structures from public implementations

- Account summary is wrapped as data.biz_data; observed fields include normal_wallets, bonus_wallets, and cost summary fields.
- Daily amount buckets have series[], each with model and buckets[]; a bucket includes time and a usage map.
- Observed usage types include PROMPT_TOKEN, PROMPT_CACHE_HIT_TOKEN, PROMPT_CACHE_MISS_TOKEN, RESPONSE_TOKEN, and REQUEST.
- Daily cost buckets include currency groups with model series and bucket cost values.
- The newer by-API-key bucket route takes Unix-second start and end values and a tz offset in seconds. The reference implementation uses GMT+8 (28800) to match the console's day buckets.

These payload observations are community-reported, not guaranteed by DeepSeek. The app validates response envelopes and parses fields defensively.

## Important product limitations

- The daily usage endpoints provide aggregate daily/model values, not a verified per-request event feed.
- The app must not fabricate per-request rows or request IDs.
- The API usage field in a model response describes that single response; it does not reveal past activity from other clients.
- Historical usage beyond the range exposed by the console must remain unavailable.
