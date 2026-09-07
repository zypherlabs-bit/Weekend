# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability, please report it responsibly.

**DO NOT** open a public issue for security vulnerabilities.

Instead, please email us at security@weekend.app with:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge receipt within 24 hours and provide a detailed response within 7 days.

## Security Measures

### Application Security
- TLS 1.2+ for all network communication
- Certificate pinning for API endpoints
- EncryptedSharedPreferences with Android Keystore for token storage
- ProGuard/R8 obfuscation for release builds
- Root/tamper detection
- No hardcoded secrets in source code

### Backend Security
- OAuth 2.0 / JWT with short-lived access tokens
- Refresh token rotation
- Rate limiting on all endpoints
- Request validation and sanitization
- SQL injection protection via parameterized queries
- CSRF protection
- Security headers (CORS, CSP, HSTS)
- Encryption at rest for sensitive data
- Audit logging for admin actions

### Data Protection
- Personal information classification
- Least privilege access
- End-to-end encryption for messages
- Automatic data deletion on account removal
- GDPR/CCPA compliance

### Monitoring
- API error rate monitoring
- Suspicious activity detection
- Rate limit abuse detection
- Anomaly detection for scam patterns
