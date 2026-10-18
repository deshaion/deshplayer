package com.example.deshplayer

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : AudioServiceActivity() {
    private var exportResult: MethodChannel.Result? = null
    private var exportFiles = emptyList<Map<String, String>>()
    private val folderRequest = 4201

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "deshplayer/cache_export")
            .setMethodCallHandler { call, result ->
                if (call.method != "exportTracks") {
                    result.notImplemented()
                } else if (exportResult != null) {
                    result.error("busy", "A copy is already in progress.", null)
                } else {
                    val files = call.argument<List<Map<String, String>>>("files")
                    if (files.isNullOrEmpty() || files.any {
                        it["path"].isNullOrBlank() || it["name"].isNullOrBlank()
                    }) {
                        result.error("invalid_files", "No valid tracks selected.", null)
                        return@setMethodCallHandler
                    }
                    exportFiles = files
                    exportResult = result
                    try {
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        }, folderRequest)
                    } catch (error: Exception) {
                        exportResult = null
                        exportFiles = emptyList()
                        result.error("folder_picker", "Could not open the folder picker.", error.toString())
                    }
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != folderRequest) return
        val result = exportResult ?: return
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            exportResult = null
            exportFiles = emptyList()
            result.success(null)
            return
        }
        val files = exportFiles
        // Stream file bytes off the UI thread, including for cloud document providers.
        Thread {
            try {
                val parent = DocumentsContract.buildDocumentUriUsingTree(
                    tree, DocumentsContract.getTreeDocumentId(tree)
                )
                val names = existingNames(tree)
                var copied = 0
                val failed = mutableListOf<String>()
                val errors = mutableListOf<String>()
                for (entry in files) {
                    val name = entry.getValue("name")
                    var destination: Uri? = null
                    try {
                        val source = File(entry.getValue("path"))
                        check(source.isFile && source.length() > 0)
                        val uniqueName = uniqueName(name, names)
                        val extension = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
                        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                            ?: "application/octet-stream"
                        destination = DocumentsContract.createDocument(
                            contentResolver, parent, mime, uniqueName
                        ) ?: error("Could not create destination")
                        val output = contentResolver.openOutputStream(destination, "w")
                            ?: error("Could not open destination")
                        output.use { sink ->
                            source.inputStream().use { input -> input.copyTo(sink) }
                        }
                        copied++
                    } catch (error: Exception) {
                        destination?.let { uri ->
                            try { DocumentsContract.deleteDocument(contentResolver, uri) }
                            catch (_: Exception) { /* Best effort removal of an incomplete copy. */ }
                        }
                        failed.add(name)
                        errors.add("$name: $error")
                    }
                }
                runOnUiThread {
                    if (exportResult === result) {
                        exportResult = null
                        exportFiles = emptyList()
                        result.success(mapOf("copied" to copied, "failed" to failed, "errors" to errors))
                    }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (exportResult === result) {
                        exportResult = null
                        exportFiles = emptyList()
                        result.error("copy_failed", "Could not access the selected folder. Please try another folder.", error.toString())
                    }
                }
            }
        }.start()
    }

    private fun existingNames(tree: Uri): MutableSet<String> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree)
        )
        val names = mutableSetOf<String>()
        val cursor = contentResolver.query(children,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?: error("Could not read destination folder")
        cursor.use {
            while (it.moveToNext()) names.add(it.getString(0).lowercase(Locale.ROOT))
        }
        return names
    }

    private fun uniqueName(name: String, names: MutableSet<String>): String {
        val dot = name.lastIndexOf('.').takeIf { it > 0 } ?: name.length
        val stem = name.substring(0, dot)
        val extension = name.substring(dot)
        var candidate = name
        var suffix = 1
        while (!names.add(candidate.lowercase(Locale.ROOT))) {
            candidate = "$stem (${suffix++})$extension"
        }
        return candidate
    }
}
