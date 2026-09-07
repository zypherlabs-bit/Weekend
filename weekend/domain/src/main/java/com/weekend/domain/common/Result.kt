package com.weekend.domain.common

sealed class Result<T> {
    data class Success<T>(val data: T): Result<T>()
    data class Error<T>(val exception: AppException): Result<T>()
    object Loading: Result<Nothing>()
}