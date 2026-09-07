package com.weekend.domain.common

sealed class AppException(message: String? = null, cause: Throwable? = null): Exception(message, cause) {
    class NetworkException(message: String? = null, cause: Throwable? = null): AppException(message, cause)
    class AuthException(message: String? = null, cause: Throwable? = null): AppException(message, cause)
    class NotFoundException(message: String? = null, cause: Throwable? = null): AppException(message, cause)
    class ValidationException(message: String? = null, cause: Throwable? = null): AppException(message, cause)
    class ServerException(message: String? = null, cause: Throwable? = null): AppException(message, cause)
    class UnknownException(message: String? = null, cause: Throwable? = null): AppException(message, cause)
}