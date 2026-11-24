package com.danqing.novel_reader

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import java.io.File
import java.io.IOException

/**
 * 通过 Android 的 SAF 目录授权访问 OneDrive。
 *
 * 不申请整个存储权限，只使用用户在系统选择器里点选的那一个文件夹，
 * 并在其中维护 DanQingReader/books 与 DanQingReader/covers。
 */
class OneDriveTree(context: Context) {
    private val resolver: ContentResolver = context.contentResolver

    fun rootDocument(treeUri: Uri): Uri {
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
    }

    fun isAvailable(treeUri: Uri): Boolean {
        if (treeUri.scheme != "content") return false
        return try {
            displayName(treeUri).isNotEmpty()
        } catch (_: Exception) {
            false
        }
    }

    fun displayName(treeUri: Uri): String {
        val document = rootDocument(treeUri)
        val name = queryDisplayName(document)
        if (!name.isNullOrBlank()) return name
        val fallback = Uri.decode(treeUri.lastPathSegment ?: "")
        return fallback.ifBlank { "OneDrive" }
    }

    fun hasWritePermission(treeUri: Uri): Boolean {
        return try {
            val flags = queryFlags(rootDocument(treeUri))
            (flags and Document.FLAG_SUPPORTS_WRITE) != 0
        } catch (_: Exception) {
            false
        }
    }

    /** 创建 DanQingReader/books 与 DanQingReader/covers，返回三个目录的 URI。 */
    fun ensureStructure(treeUri: Uri): Map<String, String> {
        val root = rootDocument(treeUri)
        val app = ensureFolder(treeUri, root, "DanQingReader")
        val books = ensureFolder(treeUri, app, "books")
        val covers = ensureFolder(treeUri, app, "covers")
        return mapOf(
            "root" to app.toString(),
            "books" to books.toString(),
            "covers" to covers.toString(),
        )
    }

    fun folderDocument(treeUri: Uri, folder: String): Uri {
        val root = rootDocument(treeUri)
        val app = findChild(treeUri, root, "DanQingReader")
            ?: throw IOException("OneDrive 中还没有 DanQingReader 目录")
        val target = findChild(treeUri, app, folder)
            ?: throw IOException("OneDrive 中还没有 DanQingReader/$folder 目录")
        return target
    }

    fun list(treeUri: Uri, folder: String): List<Map<String, Any?>> {
        val directory = folderDocument(treeUri, folder)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getDocumentId(directory),
        )
        val rows = mutableListOf<Map<String, Any?>>()
        resolver.query(
            childrenUri,
            arrayOf(
                Document.COLUMN_DOCUMENT_ID,
                Document.COLUMN_DISPLAY_NAME,
                Document.COLUMN_MIME_TYPE,
                Document.COLUMN_SIZE,
                Document.COLUMN_LAST_MODIFIED,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val documentId = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: continue
                val mime = cursor.getString(2) ?: ""
                val size = if (cursor.isNull(3)) 0L else cursor.getLong(3)
                val modified = if (cursor.isNull(4)) 0L else cursor.getLong(4)
                rows.add(
                    mapOf(
                        "uri" to DocumentsContract.buildDocumentUriUsingTree(
                            treeUri,
                            documentId,
                        ).toString(),
                        "name" to name,
                        "size" to size,
                        "modified" to modified,
                        "isDir" to (mime == Document.MIME_TYPE_DIR),
                    ),
                )
            }
        }
        return rows
    }

    /** 把网盘文件复制到应用私有目录，返回实际字节数。 */
    fun copyToLocal(remoteUri: Uri, targetPath: String): Long {
        val target = File(targetPath)
        target.parentFile?.mkdirs()
        val input = resolver.openInputStream(remoteUri)
            ?: throw IOException("OneDrive 没有返回文件内容")
        input.use { source ->
            target.outputStream().use { output ->
                source.copyTo(output)
            }
        }
        return target.length()
    }

    /** 把本地文件写入网盘的 books/covers，同名文件会被覆盖。 */
    fun upload(treeUri: Uri, folder: String, localPath: String, name: String): Boolean {
        val source = File(localPath)
        if (!source.exists()) throw IOException("本地文件不存在")
        val safeName = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        if (safeName.isBlank()) throw IOException("文件名不能为空")
        val directory = folderDocument(treeUri, folder)
        val existing = findChild(treeUri, directory, safeName)
        val documentUri = existing ?: DocumentsContract.createDocument(
            resolver,
            directory,
            mimeTypeFor(safeName),
            safeName,
        ) ?: throw IOException("OneDrive 不允许在这里创建文件")

        val output = resolver.openOutputStream(documentUri, "wt")
            ?: throw IOException("OneDrive 没有返回可写文件")
        output.use { target ->
            source.inputStream().use { input ->
                input.copyTo(target)
            }
        }
        return true
    }

    private fun ensureFolder(treeUri: Uri, parent: Uri, name: String): Uri {
        val existing = findChild(treeUri, parent, name)
        if (existing != null) return existing
        val created = DocumentsContract.createDocument(
            resolver,
            parent,
            Document.MIME_TYPE_DIR,
            name,
        ) ?: throw IOException("OneDrive 不允许创建 $name 目录，请确认已授予读写权限")
        return created
    }

    private fun findChild(treeUri: Uri, parent: Uri, name: String): Uri? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getDocumentId(parent),
        )
        resolver.query(
            childrenUri,
            arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val displayName = cursor.getString(1) ?: continue
                if (displayName.equals(name, ignoreCase = true)) {
                    val documentId = cursor.getString(0) ?: return null
                    return DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
                }
            }
        }
        return null
    }

    private fun queryDisplayName(document: Uri): String? {
        resolver.query(document, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) return cursor.getString(0)
            }
        return null
    }

    private fun queryFlags(document: Uri): Int {
        resolver.query(document, arrayOf(Document.COLUMN_FLAGS), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) return cursor.getInt(0)
            }
        return 0
    }

    private fun mimeTypeFor(name: String): String {
        return when (name.substringAfterLast('.', "").lowercase()) {
            "epub" -> "application/epub+zip"
            "mobi" -> "application/x-mobipocket-ebook"
            "azw3", "azw" -> "application/vnd.amazon.ebook"
            "txt", "md" -> "text/plain"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            else -> "application/octet-stream"
        }
    }
}
