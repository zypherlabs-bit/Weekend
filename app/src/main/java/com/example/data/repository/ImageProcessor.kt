package com.example.data.repository

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

/**
 * Production-grade image optimization pipeline for Weekend profile photos.
 *
 * Pipeline: Original -> Validate -> Decode -> Correct orientation -> Resize -> Compress
 *
 * Targets:
 *   - Master: max 1600px on long edge, high-quality WebP
 *   - Medium: max 800px for discovery cards
 *   - Thumb: max 320px for lists/chat previews
 */
object ImageProcessor {

    private const val TAG = "WeekendImageProcessor"

    const val MAX_MASTER_DIMENSION = 1600
    const val MAX_MEDIUM_DIMENSION = 800
    const val MAX_THUMB_DIMENSION = 320

    private const val MASTER_QUALITY = 85
    private const val MEDIUM_QUALITY = 80
    private const val THUMB_QUALITY = 75

    val SUPPORTED_MIME_TYPES = setOf("image/jpeg", "image/png", "image/webp")

    data class OptimizedImage(
        val masterBytes: ByteArray,
        val mediumBytes: ByteArray,
        val thumbBytes: ByteArray,
        val width: Int,
        val height: Int,
        val mimeType: String,
        val originalSizeBytes: Long,
        val masterSizeBytes: Long,
        val mediumSizeBytes: Long,
        val thumbSizeBytes: Long
    ) {
        val compressionRatio: Float
            get() = if (originalSizeBytes > 0) {
                1f - (masterSizeBytes.toFloat() / originalSizeBytes.toFloat())
            } else 0f
    }

    data class ImageValidationResult(
        val isValid: Boolean,
        val errorMessage: String? = null,
        val mimeType: String? = null,
        val width: Int = 0,
        val height: Int = 0,
        val fileSizeBytes: Long = 0
    )

    suspend fun validateImage(
        context: Context,
        uri: Uri,
        maxSizeBytes: Long = 10 * 1024 * 1024L
    ): ImageValidationResult = withContext(Dispatchers.IO) {
        try {
            val contentResolver = context.contentResolver
            val mimeType = contentResolver.getType(uri)
            if (mimeType == null || mimeType !in SUPPORTED_MIME_TYPES) {
                return@withContext ImageValidationResult(
                    isValid = false,
                    errorMessage = "Unsupported image format. Please use JPEG, PNG, or WebP."
                )
            }

            val fileSize = contentResolver.openAssetFileDescriptor(uri, "r")?.use {
                it.length
            } ?: 0L

            if (fileSize > maxSizeBytes) {
                return@withContext ImageValidationResult(
                    isValid = false,
                    errorMessage = "Image is too large. Maximum size is ${maxSizeBytes / (1024 * 1024)} MB."
                )
            }

            if (fileSize == 0L) {
                return@withContext ImageValidationResult(
                    isValid = false,
                    errorMessage = "Image file is empty or corrupted."
                )
            }

            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, options)
            }

            if (options.outWidth <= 0 || options.outHeight <= 0) {
                return@withContext ImageValidationResult(
                    isValid = false,
                    errorMessage = "Could not read image dimensions. The file may be corrupted."
                )
            }

            if (options.outWidth < 200 || options.outHeight < 200) {
                return@withContext ImageValidationResult(
                    isValid = false,
                    errorMessage = "Image is too small. Minimum size is 200x200 pixels."
                )
            }

            ImageValidationResult(
                isValid = true,
                mimeType = mimeType,
                width = options.outWidth,
                height = options.outHeight,
                fileSizeBytes = fileSize
            )
        } catch (e: Exception) {
            Log.w(TAG, "Image validation failed: ${e.message}")
            ImageValidationResult(
                isValid = false,
                errorMessage = "Failed to read image: ${e.message}"
            )
        }
    }

    /**
     * Process an image: validate, resize, compress, and generate variants.
     */
    suspend fun processImage(
        context: Context,
        uri: Uri
    ): OptimizedImage = withContext(Dispatchers.IO) {
        val validation = validateImage(context, uri)
        if (!validation.isValid) {
            throw IllegalArgumentException(validation.errorMessage ?: "Invalid image")
        }

        val bitmap = decodeAndCorrectOrientation(context, uri)
            ?: throw IllegalStateException("Failed to decode image")

        try {
            val originalWidth = bitmap.width
            val originalHeight = bitmap.height
            val originalSize = getOriginalSize(context, uri)

            val masterBitmap = resizeBitmap(bitmap, MAX_MASTER_DIMENSION)
            val masterBytes = compressBitmap(masterBitmap, MASTER_QUALITY)

            val mediumBitmap = resizeBitmap(bitmap, MAX_MEDIUM_DIMENSION)
            val mediumBytes = compressBitmap(mediumBitmap, MEDIUM_QUALITY)

            val thumbBitmap = resizeBitmap(bitmap, MAX_THUMB_DIMENSION)
            val thumbBytes = compressBitmap(thumbBitmap, THUMB_QUALITY)

            val result = OptimizedImage(
                masterBytes = masterBytes,
                mediumBytes = mediumBytes,
                thumbBytes = thumbBytes,
                width = masterBitmap.width,
                height = masterBitmap.height,
                mimeType = "image/webp",
                originalSizeBytes = originalSize,
                masterSizeBytes = masterBytes.size.toLong(),
                mediumSizeBytes = mediumBytes.size.toLong(),
                thumbSizeBytes = thumbBytes.size.toLong()
            )

            Log.i(
                TAG,
                "Image processed: ${originalWidth}x${originalHeight} (${formatBytes(originalSize)}) " +
                "-> ${masterBitmap.width}x${masterBitmap.height} (${formatBytes(masterBytes.size.toLong())}) " +
                "compression: ${(result.compressionRatio * 100).toInt()}%"
            )

            if (masterBitmap != bitmap) masterBitmap.recycle()
            if (mediumBitmap != bitmap) mediumBitmap.recycle()
            if (thumbBitmap != bitmap) thumbBitmap.recycle()

            result
        } finally {
            bitmap.recycle()
        }
    }

    /**
     * Decode a bitmap from URI and correct its orientation based on EXIF data.
     */
    private fun decodeAndCorrectOrientation(context: Context, uri: Uri): Bitmap? {
        val contentResolver = context.contentResolver

        val bitmap = contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream)
        } ?: return null

        return try {
            contentResolver.openInputStream(uri)?.use { stream ->
                val exif = ExifInterface(stream)
                val orientation = exif.getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL
                )

                val matrix = Matrix()
                when (orientation) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                    ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                    ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                    ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
                    ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
                    else -> return bitmap
                }

                Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            } ?: bitmap
        } catch (e: Exception) {
            Log.w(TAG, "Could not read EXIF orientation: ${e.message}")
            bitmap
        }
    }

    /**
     * Resize a bitmap so its longest edge fits within maxDimension while preserving aspect ratio.
     */
    private fun resizeBitmap(bitmap: Bitmap, maxDimension: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height

        if (width <= maxDimension && height <= maxDimension) {
            return bitmap
        }

        val scale = if (width > height) {
            maxDimension.toFloat() / width
        } else {
            maxDimension.toFloat() / height
        }

        val newWidth = (width * scale).toInt().coerceAtLeast(1)
        val newHeight = (height * scale).toInt().coerceAtLeast(1)

        return Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
    }

    /**
     * Compress a bitmap to WebP format with the specified quality.
     */
    private fun compressBitmap(bitmap: Bitmap, quality: Int): ByteArray {
        return ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.WEBP, quality, stream)
            stream.toByteArray()
        }
    }

    private fun getOriginalSize(context: Context, uri: Uri): Long {
        return try {
            context.contentResolver.openAssetFileDescriptor(uri, "r")?.use {
                it.length
            } ?: 0L
        } catch (e: Exception) {
            0L
        }
    }

    private fun formatBytes(bytes: Long): String {
        return when {
            bytes >= 1024 * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024.0))
            bytes >= 1024 -> String.format("%.1f KB", bytes / 1024.0)
            else -> "$bytes B"
        }
    }
}
