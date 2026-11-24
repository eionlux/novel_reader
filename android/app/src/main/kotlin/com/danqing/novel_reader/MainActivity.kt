package com.danqing.novel_reader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var openChannel: MethodChannel? = null
    private var pendingPath: String? = null
    private var dartReady = false

    private lateinit var oneDriveTree: OneDriveTree
    private var pendingTreePick: MethodChannel.Result? = null

    companion object {
        private const val REQUEST_PICK_TREE = 4311
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.danqing.novel_reader/app_paths")
            .setMethodCallHandler { call, result ->
                if (call.method == "appDataDirectory") {
                    result.success(filesDir.absolutePath)
                } else {
                    result.notImplemented()
                }
            }

        openChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.danqing.novel_reader/open_file")
        openChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingFile" -> {
                    val path = pendingPath
                    pendingPath = null
                    result.success(path)
                }
                "notifyReady" -> {
                    dartReady = true
                    val path = pendingPath
                    if (path != null) {
                        pendingPath = null
                        openChannel?.invokeMethod("openFile", path)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        oneDriveTree = OneDriveTree(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.danqing.novel_reader/one_drive")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolder" -> pickOneDriveFolder(result)
                    "check" -> {
                        val uri = parseUri(call.arguments as? Map<*, *>, result) ?: return@setMethodCallHandler
                        runTreeTask(result) {
                            mapOf(
                                "available" to oneDriveTree.isAvailable(uri),
                                "label" to oneDriveTree.displayName(uri),
                                "writable" to (oneDriveTree.hasWritePermission(uri) || hasPersistedWrite(uri)),
                                "persisted" to hasPersistedRead(uri),
                            )
                        }
                    }
                    "ensureStructure" -> {
                        val uri = parseUri(call.arguments as? Map<*, *>, result) ?: return@setMethodCallHandler
                        runTreeTask(result) { oneDriveTree.ensureStructure(uri) }
                    }
                    "list" -> {
                        val uri = parseUri(call.arguments as? Map<*, *>, result) ?: return@setMethodCallHandler
                        val folder = (call.arguments as? Map<*, *>)?.get("folder") as? String ?: "books"
                        runTreeTask(result) { oneDriveTree.list(uri, folder) }
                    }
                    "copyToLocal" -> {
                        val args = call.arguments as? Map<*, *>
                        val uri = parseUri(args, result) ?: return@setMethodCallHandler
                        val target = args?.get("targetPath") as? String
                        if (target.isNullOrBlank()) {
                            result.error("one_drive", "缺少本地目标路径", null)
                            return@setMethodCallHandler
                        }
                        runTreeTask(result) { oneDriveTree.copyToLocal(uri, target) }
                    }
                    "upload" -> {
                        val args = call.arguments as? Map<*, *>
                        val uri = parseUri(args, result) ?: return@setMethodCallHandler
                        val folder = args?.get("folder") as? String ?: "books"
                        val localPath = args?.get("localPath") as? String
                        val name = args?.get("name") as? String
                        if (localPath.isNullOrBlank() || name.isNullOrBlank()) {
                            result.error("one_drive", "缺少本地文件或文件名", null)
                            return@setMethodCallHandler
                        }
                        runTreeTask(result) {
                            oneDriveTree.upload(uri, folder, localPath, name)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickOneDriveFolder(result: MethodChannel.Result) {
        if (pendingTreePick != null) {
            result.error("one_drive_busy", "已经打开一个文件夹选择器", null)
            return
        }
        pendingTreePick = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                )
                putExtra("android.content.extra.SHOW_ADVANCED", true)
            }
            startActivityForResult(intent, REQUEST_PICK_TREE)
        } catch (e: Exception) {
            pendingTreePick = null
            result.error("one_drive", "当前系统无法打开文件夹选择器：${e.message}", null)
        }
    }

    private fun parseUri(args: Map<*, *>?, result: MethodChannel.Result): Uri? {
        val raw = args?.get("uri") as? String
        if (raw.isNullOrBlank()) {
            result.error("one_drive", "缺少 OneDrive 目录 URI", null)
            return null
        }
        return try {
            Uri.parse(raw)
        } catch (e: Exception) {
            result.error("one_drive", "OneDrive 目录 URI 无效：${e.message}", null)
            null
        }
    }

    private fun runTreeTask(result: MethodChannel.Result, block: () -> Any?) {
        Thread {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("one_drive", e.message ?: "OneDrive 目录操作失败", null)
                }
            }
        }.start()
    }

    private fun hasPersistedRead(uri: Uri): Boolean = try {
        contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }
    } catch (_: Exception) {
        false
    }

    private fun hasPersistedWrite(uri: Uri): Boolean = try {
        contentResolver.persistedUriPermissions.any { it.uri == uri && it.isWritePermission }
    } catch (_: Exception) {
        false
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_TREE) return
        val pending = pendingTreePick
        pendingTreePick = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending?.success(null)
            return
        }
        val uri = data.data!!
        try {
            val takeFlags = data.flags and (
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            if (takeFlags != 0) {
                contentResolver.takePersistableUriPermission(uri, takeFlags)
            }
            pending?.success(
                mapOf(
                    "uri" to uri.toString(),
                    "label" to oneDriveTree.displayName(uri),
                    "writable" to (oneDriveTree.hasWritePermission(uri) || hasPersistedWrite(uri)),
                ),
            )
        } catch (e: Exception) {
            pending?.error("one_drive", "无法保存 OneDrive 授权：${e.message}", null)
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_VIEW) return
        val uri: Uri = intent.data ?: return
        val path = copyToCache(uri) ?: return
        if (dartReady) {
            openChannel?.invokeMethod("openFile", path)
        } else {
            pendingPath = path
        }
    }

    /** 把外部 content:// 或 file:// 文件复制到缓存目录，返回真实文件路径 */
    private fun copyToCache(uri: Uri): String? {
        return try {
            val name = queryDisplayName(uri) ?: uri.lastPathSegment ?: "external_book"
            val fileName = withBookExtension(uri, name)
            val dir = File(cacheDir, "opened")
            if (!dir.exists()) dir.mkdirs()
            val target = File(dir, fileName.replace(Regex("[\\\\/:*?\"<>|]"), "_"))
            if (target.exists()) target.delete()
            when (uri.scheme) {
                "content" -> {
                    contentResolver.openInputStream(uri)?.use { input ->
                        target.outputStream().use { output -> input.copyTo(output) }
                    } ?: return null
                }
                "file" -> {
                    val source = File(uri.path ?: return null)
                    if (!source.exists()) return null
                    source.copyTo(target, overwrite = true)
                }
                else -> return null
            }
            target.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private fun withBookExtension(uri: Uri, name: String): String {
        val supported = Regex("\\.(txt|md|epub|mobi|azw3|azw)$", RegexOption.IGNORE_CASE)
        if (supported.containsMatchIn(name)) return name
        val extension = when (contentResolver.getType(uri)) {
            "application/epub+zip" -> ".epub"
            "application/x-mobipocket-ebook" -> ".mobi"
            "application/vnd.amazon.ebook" -> ".azw3"
            "text/plain", "text/markdown" -> ".txt"
            else -> ""
        }
        return name + extension
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (e: Exception) {
            null
        }
    }
}
