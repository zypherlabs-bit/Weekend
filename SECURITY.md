# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅        |

## Reporting a Vulnerability

If you discover a security vulnerability in Weekend, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities
2. Email the maintainers with a detailed description of the vulnerability
3. Include steps to reproduce and potential impact
4. Allow reasonable time for a fix before public disclosure

## Security Architecture

Weekend is designed with security as a core principle:

### Backend Security
- **Supabase Auth**: Email/password authentication with email verification
- **Row Level Security (RLS)**: Enabled on every database table
- **Server-side authorization**: All security-critical decisions happen server-side
- **PostGIS**: Location data is processed server-side; exact coordinates are never exposed

### Client Security
- **No secrets in code**: Only public anon keys are embedded in the app
- **HTTPS only**: All network traffic uses TLS
- **Session management**: Secure token-based authentication
- **Input validation**: Both client-side (UX) and server-side (security)

### Data Privacy
- **Location privacy**: Only approximate distance/city is shown to other users
- **No exact GPS**: Raw coordinates are never stored in accessible form
- **Account deletion**: Complete server-side data removal
- **Photo verification**: AI-powered real-human verification

### Anti-Abuse
- **Rate limiting**: API request throttling via Supabase
- **Scam detection**: Layered AI-powered scam detection
- **Photo moderation**: Multi-signal image verification
- **Block/report**: User-driven moderation tools

## Security Limitations

Weekend is open source. The security model assumes:

- Attackers can inspect the APK and source code
- Attackers can inspect network traffic
- Attackers can call APIs directly

Therefore, **all authorization is enforced server-side** via Supabase RLS and database constraints. The client is considered fully inspectable.

**Weekend cannot be:**
- 100% reverse-engineering proof
- Impossible to DDoS
- Completely immune to all attacks

Instead, Weekend implements **defense-in-depth** with server-side enforcement, rate limiting, and abuse detection.

## Dependencies

Key security-relevant dependencies are kept up to date. Run `./gradlew dependencies` to review.

## Responsible Disclosure

We appreciate responsible security research and will acknowledge contributors who help improve Weekend's security.
