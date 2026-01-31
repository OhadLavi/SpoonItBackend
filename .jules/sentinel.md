## 2025-05-23 - Logic Flaw in Private IP Blocking
**Vulnerability:** The `validate_url` function correctly identified private IP prefixes (`10.`, `192.168.`) but due to a nested `if` structure, it only raised an error for `172.16-31` range. All other private IPs passed through without restriction.
**Learning:** Nested conditional logic in security validators can silently fail open. Security checks should be flat and explicit (fail-fast).
**Prevention:** Use established libraries (`ipaddress`) instead of custom string parsing logic. Verify every branch of security logic with negative tests.
