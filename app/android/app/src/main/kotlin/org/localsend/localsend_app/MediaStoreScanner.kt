package org.localsend.localsend_app

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import java.io.File

private const val LEGACY_EXTERNAL_VOLUME = "external"

data class BackupMediaItem(
    val mediaKey: String,
    val contentUri: String,
    val relativePath: String,
    val displayName: String,
    val sizeBytes: Long,
    val modifiedAtSeconds: Long,
    val generationModified: Long?,
    val mimeType: String,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "mediaKey" to mediaKey,
        "contentUri" to contentUri,
        "relativePath" to relativePath,
        "displayName" to displayName,
        "sizeBytes" to sizeBytes,
        "modifiedAtSeconds" to modifiedAtSeconds,
        "generationModified" to generationModified,
        "mimeType" to mimeType,
    )
}

data class BackupMediaPage(
    val items: List<BackupMediaItem>,
    val nextAfterId: Long,
    val hasMore: Boolean,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "items" to items.map { it.toMap() },
        "nextAfterId" to nextAfterId,
        "hasMore" to hasMore,
    )
}

class MediaStoreScanner(
    context: Context,
) {
    private val appContext = context.applicationContext
    private val contentResolver = appContext.contentResolver

    fun scan(
        afterId: Long,
        limit: Int,
        includeImages: Boolean,
        includeVideos: Boolean,
    ): BackupMediaPage {
        if (!includeImages && !includeVideos) {
            return BackupMediaPage(
                items = emptyList(),
                nextAfterId = afterId,
                hasMore = false,
            )
        }

        val collectionUri = externalFilesUri()
        val projection = buildProjection()
        val (selection, selectionArgs) = buildSelection(
            afterId = afterId,
            includeImages = includeImages,
            includeVideos = includeVideos,
        )
        // _ID values are only unique inside a physical volume. A merged VOLUME_EXTERNAL
        // query can therefore contain several rows with the same _ID. Leave enough room
        // for the complete boundary group plus one lookahead row.
        val pageSizeWithLookahead = limit + externalVolumeCount()
        val scannedItems = ArrayList<BackupMediaItemWithId>(pageSizeWithLookahead)
        var boundaryId: Long? = null
        var hasMore = false

        query(
            collectionUri = collectionUri,
            projection = projection,
            selection = selection,
            selectionArgs = selectionArgs,
            limit = pageSizeWithLookahead,
        )?.use { cursor ->
            val columns = MediaColumns(cursor)
            while (cursor.moveToNext()) {
                val item = columns.readItem(cursor, collectionUri)
                if (boundaryId != null && item.mediaId != boundaryId) {
                    hasMore = true
                    break
                }
                scannedItems.add(item)
                if (scannedItems.size == limit) {
                    boundaryId = item.mediaId
                }
            }
        }

        return BackupMediaPage(
            items = scannedItems.map { it.item },
            nextAfterId = scannedItems.lastOrNull()?.mediaId ?: afterId,
            hasMore = hasMore,
        )
    }

    private fun query(
        collectionUri: Uri,
        projection: Array<String>,
        selection: String,
        selectionArgs: Array<String>,
        limit: Int,
    ): Cursor? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val queryArgs = Bundle().apply {
                putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, selectionArgs)
                putStringArray(
                    ContentResolver.QUERY_ARG_SORT_COLUMNS,
                    sortColumns(),
                )
                putInt(
                    ContentResolver.QUERY_ARG_SORT_DIRECTION,
                    ContentResolver.QUERY_SORT_DIRECTION_ASCENDING,
                )
                putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
            }

            try {
                return contentResolver.query(
                    collectionUri,
                    projection,
                    queryArgs,
                    null,
                )
            } catch (_: IllegalArgumentException) {
                // Some vendor MediaProviders advertise structured query arguments but reject them.
            } catch (_: UnsupportedOperationException) {
                // Fall through to the API 21 query shape.
            }
        }

        return contentResolver.query(
            collectionUri,
            projection,
            selection,
            selectionArgs,
            sortColumns().joinToString(", ") { "$it ASC" },
        )
    }

    private fun buildProjection(): Array<String> = buildList {
        add(MediaStore.Files.FileColumns._ID)
        add(MediaStore.MediaColumns.DISPLAY_NAME)
        add(MediaStore.MediaColumns.SIZE)
        add(MediaStore.MediaColumns.DATE_MODIFIED)
        add(MediaStore.MediaColumns.MIME_TYPE)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            add(MediaStore.MediaColumns.VOLUME_NAME)
            add(MediaStore.MediaColumns.RELATIVE_PATH)
        } else {
            @Suppress("DEPRECATION")
            add(MediaStore.MediaColumns.DATA)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            add(MediaStore.MediaColumns.GENERATION_MODIFIED)
        }
    }.toTypedArray()

    private fun buildSelection(
        afterId: Long,
        includeImages: Boolean,
        includeVideos: Boolean,
    ): Pair<String, Array<String>> {
        val mediaTypeValues = buildList {
            if (includeImages) {
                add(MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString())
            }
            if (includeVideos) {
                add(MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString())
            }
        }
        val mediaTypeClause = mediaTypeValues.joinToString(
            separator = " OR ",
            prefix = "(",
            postfix = ")",
        ) { "${MediaStore.Files.FileColumns.MEDIA_TYPE} = ?" }
        val clauses = mutableListOf(
            mediaTypeClause,
            "${MediaStore.Files.FileColumns._ID} > ?",
            "${MediaStore.MediaColumns.DISPLAY_NAME} IS NOT NULL",
            "${MediaStore.MediaColumns.DISPLAY_NAME} != ''",
            "${MediaStore.MediaColumns.MIME_TYPE} IS NOT NULL",
            "${MediaStore.MediaColumns.MIME_TYPE} != ''",
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            clauses.add("${MediaStore.MediaColumns.IS_PENDING} = 0")
            clauses.add("${MediaStore.MediaColumns.VOLUME_NAME} IS NOT NULL")
            clauses.add("${MediaStore.MediaColumns.VOLUME_NAME} != ''")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            clauses.add("${MediaStore.MediaColumns.IS_TRASHED} = 0")
        }

        return clauses.joinToString(" AND ") to
            (mediaTypeValues + afterId.toString()).toTypedArray()
    }

    private fun externalFilesUri(): Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
    } else {
        MediaStore.Files.getContentUri(LEGACY_EXTERNAL_VOLUME)
    }

    private fun externalVolumeCount(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        MediaStore.getExternalVolumeNames(appContext).size.coerceAtLeast(1)
    } else {
        1
    }

    private fun sortColumns(): Array<String> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.MediaColumns.VOLUME_NAME,
        )
    } else {
        arrayOf(MediaStore.Files.FileColumns._ID)
    }

    private class MediaColumns(cursor: Cursor) {
        private val id = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
        private val displayName = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
        private val size = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
        private val modifiedAt = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
        private val mimeType = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
        private val volumeName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.VOLUME_NAME)
        } else {
            -1
        }
        private val relativePath = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH)
        } else {
            -1
        }
        private val data = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            @Suppress("DEPRECATION")
            cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
        } else {
            -1
        }
        private val generationModified = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.GENERATION_MODIFIED)
        } else {
            -1
        }

        fun readItem(cursor: Cursor, aggregateUri: Uri): BackupMediaItemWithId {
            val mediaId = cursor.getLong(id)
            val volume = cursor.stringOrNull(volumeName) ?: LEGACY_EXTERNAL_VOLUME
            val itemUri = ContentUris.withAppendedId(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    MediaStore.Files.getContentUri(volume)
                } else {
                    aggregateUri
                },
                mediaId,
            )

            return BackupMediaItemWithId(
                mediaId = mediaId,
                item = BackupMediaItem(
                    mediaKey = "$volume:$mediaId",
                    contentUri = itemUri.toString(),
                    relativePath = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        cursor.stringOrNull(relativePath).orEmpty()
                    } else {
                        legacyRelativePath(cursor.stringOrNull(data))
                    },
                    displayName = cursor.stringOrNull(displayName).orEmpty(),
                    sizeBytes = cursor.longOrZero(size).coerceAtLeast(0L),
                    modifiedAtSeconds = cursor.longOrZero(modifiedAt).coerceAtLeast(0L),
                    generationModified = cursor.longOrNull(generationModified)?.takeIf { it >= 0L },
                    mimeType = cursor.stringOrNull(mimeType).orEmpty(),
                ),
            )
        }

        private fun legacyRelativePath(dataPath: String?): String {
            val parent = dataPath?.let(::File)?.parent ?: return ""
            @Suppress("DEPRECATION")
            val primaryRoot = Environment.getExternalStorageDirectory().absolutePath
            val relative = if (parent == primaryRoot) {
                ""
            } else if (parent.startsWith("$primaryRoot${File.separator}")) {
                parent.substring(primaryRoot.length + 1)
            } else {
                parent.trimStart(File.separatorChar)
            }
            return if (relative.isEmpty()) "" else "$relative/"
        }
    }
}

private data class BackupMediaItemWithId(
    val mediaId: Long,
    val item: BackupMediaItem,
)

private fun Cursor.stringOrNull(columnIndex: Int): String? =
    if (columnIndex < 0 || isNull(columnIndex)) null else getString(columnIndex)

private fun Cursor.longOrNull(columnIndex: Int): Long? =
    if (columnIndex < 0 || isNull(columnIndex)) null else getLong(columnIndex)

private fun Cursor.longOrZero(columnIndex: Int): Long = longOrNull(columnIndex) ?: 0L
