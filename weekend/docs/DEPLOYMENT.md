# Deployment Guide

## Environments

- **Development**: Local development, Firebase emulators
- **Staging**: Pre-production testing, separate Firebase project
- **Production**: Live app, Google Play Store

## Prerequisites

- Android Studio
- JDK 17
- Gradle 8.11+
- Firebase project configured
- Google Play Console access
- Signing keystore

## Android App Deployment

### Generate Signed APK/AAB

1. In Android Studio: `Build > Generate Signed Bundle / APK`
2. Select `Android App Bundle` for Play Store
3. Choose keystore or create new one
4. Select `release` build variant
5. Complete wizard

### Google Play Store

1. Create app in Google Play Console
2. Complete store listing (screenshots, description, etc.)
3. Upload AAB
4. Configure production, beta, alpha tracks
5. Set up pre-launch report
6. Rollout to production

## Backend Deployment

### Infrastructure

Recommended stack:
- **Compute**: Docker containers on Kubernetes or Cloud Run
- **Database**: PostgreSQL (managed service preferred)
- **Cache**: Redis (managed service)
- **Storage**: Cloud storage with CDN
- **WebSockets**: Managed WebSocket gateway
- **Push Notifications**: Firebase Cloud Messaging

### Environment Variables

Set in deployment environment:
```
DATABASE_URL=postgresql://...
REDIS_URL=redis://...
JWT_SECRET=...
FIREBASE_PROJECT_ID=...
STORAGE_BUCKET=...
MODERATION_API_KEY=...
```

### CI/CD Pipeline

GitHub Actions:
1. Run tests
2. Build artifacts
3. Security scan
4. Deploy to staging
5. Run integration tests
6. Deploy to production (with approval)

## Monitoring

- Crash reporting (Firebase Crashlytics)
- Performance monitoring
- API latency tracking
- Error rate alerts
- Database connection monitoring

## Rollback

1. Keep previous versions ready
2. Monitor after deployment
3. Rollback if error rate exceeds threshold
