# API Documentation

## Base URL
Production: `https://api.weekend.app/v1`
Staging: `https://staging-api.weekend.app/v1`

## Authentication

All authenticated endpoints require:
```
Authorization: Bearer <access_token>
```

### POST /auth/otp/request
Request OTP for phone authentication.

**Request:**
```json
{
  "phone": "+919876543210"
}
```

**Response:**
```json
{
  "success": true,
  "data": { "requestId": "req_123" },
  "error": null,
  "requestId": "req_123"
}
```

### POST /auth/otp/verify
Verify OTP and get tokens.

**Request:**
```json
{
  "phone": "+919876543210",
  "otp": "123456"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "accessToken": "eyJ...",
    "refreshToken": "eyJ...",
    "user": { "id": "user_123", "name": "Max" }
  },
  "error": null,
  "requestId": "req_123"
}
```

### POST /auth/email/signin
Email/passwordless authentication.

**Request:**
```json
{
  "email": "max@example.com"
}
```

### POST /auth/google
Google Sign-In token exchange.

**Request:**
```json
{
  "idToken": "eyJ..."
}
```

## Profile

### GET /profile/me
Get current user profile.

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "user_123",
    "name": "Max",
    "age": 26,
    "photos": ["https://..."],
    "bio": "...",
    "interests": ["Coffee", "Hiking"],
    "isVerified": true
  },
  "error": null
}
```

### PATCH /profile/me
Update profile.

**Request:**
```json
{
  "name": "Max",
  "bio": "Updated bio",
  "interests": ["Coffee", "Hiking", "Music"]
}
```

### POST /profile/photos
Upload profile photo.

**Request:** `multipart/form-data`
- `photo`: image file

## Discovery

### GET /discovery
Get discovery profiles with filters.

**Query Parameters:**
- `mode`: `for_you` | `nearby` | `crossed_paths` | `interests`
- `maxDistance`: integer (km)
- `minAge`: integer
- `maxAge`: integer

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "user_456",
      "name": "Aanya",
      "age": 24,
      "photos": ["https://..."],
      "distanceKm": 3,
      "interests": ["Coffee", "Hiking"]
    }
  ]
}
```

### POST /discovery/{profileId}/like
Like a profile.

**Response:**
```json
{
  "success": true,
  "data": { "isMatch": true },
  "error": null
}
```

### POST /discovery/{profileId}/pass
Pass on a profile.

### POST /discovery/{profileId}/super-like
Super like a profile.

## Matches

### GET /matches
Get user's matches.

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "match_123",
      "user": { "id": "user_456", "name": "Aanya" },
      "lastMessage": "Hey!",
      "unreadCount": 1
    }
  ]
}
```

### POST /matches/{matchId}/extend
Extend match expiration.

### DELETE /matches/{matchId}
Unmatch.

## Messaging

### GET /conversations/{conversationId}/messages
Get messages with pagination.

**Query Parameters:**
- `limit`: integer (default 50)
- `before`: timestamp cursor

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "msg_123",
      "senderId": "user_456",
      "text": "Hey!",
      "timestamp": 1234567890,
      "isRead": true
    }
  ]
}
```

### POST /conversations/{conversationId}/messages
Send a message.

**Request:**
```json
{
  "text": "Hello!"
}
```

## Safety

### POST /users/{userId}/block
Block a user.

### POST /users/{userId}/report
Report a user.

**Request:**
```json
{
  "reason": "harassment",
  "details": "User sent inappropriate messages"
}
```

## Error Codes

| Code | Description |
|------|-------------|
| `NETWORK_ERROR` | Network connectivity issue |
| `AUTH_REQUIRED` | Authentication required |
| `RATE_LIMITED` | Too many requests |
| `PROFILE_NOT_FOUND` | Profile does not exist |
| `USER_BLOCKED` | User is blocked |
| `MATCH_EXPIRED` | Match has expired |
| `SERVER_ERROR` | Internal server error |
