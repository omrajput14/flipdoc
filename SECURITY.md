# Security Policy

## Supported Versions

| Version | Supported |
| :--- | :--- |
| `v2.1.x` (Current Beta) | :white_check_mark: |
| `< v2.0` | :x: |

## Security Architecture

- **100% Offline Execution**: MELD does not open network listeners or transmit user files over the internet.
- **Non-Destructive File Output**: Every conversion and tool operation writes to a collision-safe sibling path via `OutputNaming.uniqueFileURL(nextTo:)` and never overwrites original user files in place.
- **Physical Pixel Redaction (`RedactionEngine`)**: When redacting sensitive PII (emails, phone numbers, IDs, currency amounts, or custom terms) in PDFs or images, MELD rasterizes pages at 216 DPI and burns opaque black bars directly into the pixel buffer rather than placing removable PDF vector annotations over selectable text.

## Reporting a Vulnerability

If you discover a security issue or vulnerability in MELD:
1. Please report it via [GitHub Security Advisories](https://github.com/meld-app/meld-mac/security/advisories/new) or open an issue at https://github.com/meld-app/meld-mac/issues.
2. Include steps to reproduce, macOS version, and sample file type (without sensitive personal data).
