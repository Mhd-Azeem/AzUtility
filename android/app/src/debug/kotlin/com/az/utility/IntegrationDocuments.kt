package com.az.utility

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract as D
import android.provider.DocumentsProvider
import java.io.File

/** Debug APK only. A private test provider, never part of release artifacts. */
class IntegrationDocuments : DocumentsProvider() {
  private val root get()=File(context!!.cacheDir,"integration-documents")
  override fun onCreate():Boolean {
    root.deleteRecursively(); root.mkdirs()
    File(root,"a.txt").writeText("AZ provider integration")
    File(root,"b.txt").writeText("AZ provider integration")
    File(root,"destination").mkdir()
    java.util.zip.ZipOutputStream(File(root,"unsafe.zip").outputStream()).use { zip -> zip.putNextEntry(java.util.zip.ZipEntry("../escaped.txt")); zip.write("unsafe".toByteArray()); zip.closeEntry() }
    return true
  }
  private fun file(id:String):File {
    require(id=="root" || id.startsWith("root/"))
    val f=if(id=="root") root else File(root,id.removePrefix("root/"))
    require(f.canonicalPath==root.canonicalPath || f.canonicalPath.startsWith(root.canonicalPath+File.separator))
    return f
  }
  private fun id(f:File)=if(f==root) "root" else "root/"+f.relativeTo(root).path.replace('\\','/')
  private val columns=arrayOf(D.Document.COLUMN_DOCUMENT_ID,D.Document.COLUMN_DISPLAY_NAME,D.Document.COLUMN_MIME_TYPE,D.Document.COLUMN_SIZE,D.Document.COLUMN_LAST_MODIFIED,D.Document.COLUMN_FLAGS)
  private fun row(cursor:MatrixCursor,f:File) {
    val values=mapOf(D.Document.COLUMN_DOCUMENT_ID to id(f),D.Document.COLUMN_DISPLAY_NAME to f.name,D.Document.COLUMN_MIME_TYPE to if(f.isDirectory) D.Document.MIME_TYPE_DIR else if(f.extension=="zip") "application/zip" else "text/plain",D.Document.COLUMN_SIZE to f.length(),D.Document.COLUMN_LAST_MODIFIED to f.lastModified(),D.Document.COLUMN_FLAGS to (D.Document.FLAG_SUPPORTS_WRITE or D.Document.FLAG_SUPPORTS_DELETE or D.Document.FLAG_SUPPORTS_RENAME or if(f.isDirectory) D.Document.FLAG_DIR_SUPPORTS_CREATE else 0))
    cursor.addRow(cursor.columnNames.map { values[it] }.toTypedArray())
  }
  override fun queryRoots(projection:Array<out String>?):Cursor = MatrixCursor(arrayOf(D.Root.COLUMN_ROOT_ID,D.Root.COLUMN_DOCUMENT_ID,D.Root.COLUMN_TITLE,D.Root.COLUMN_FLAGS)).apply { addRow(arrayOf("root","root","AZ Integration",D.Root.FLAG_SUPPORTS_CREATE or D.Root.FLAG_SUPPORTS_IS_CHILD)) }
  override fun queryDocument(documentId:String,projection:Array<out String>?):Cursor=MatrixCursor(projection ?: columns).apply { row(this,file(documentId)) }
  override fun queryChildDocuments(parentDocumentId:String,projection:Array<out String>?,sortOrder:String?):Cursor=MatrixCursor(projection ?: columns).apply { for(f in file(parentDocumentId).listFiles() ?: emptyArray()) row(this,f) }
  override fun getDocumentType(documentId:String):String=if(file(documentId).isDirectory) D.Document.MIME_TYPE_DIR else "text/plain"
  override fun openDocument(documentId:String,mode:String,signal:CancellationSignal?):ParcelFileDescriptor=ParcelFileDescriptor.open(file(documentId),ParcelFileDescriptor.parseMode(mode))
  override fun createDocument(parentDocumentId:String,mimeType:String,displayName:String):String {
    require(displayName.isNotBlank() && !displayName.contains('/') && !displayName.contains('\\'))
    val target=File(file(parentDocumentId),displayName); check(!target.exists())
    if(mimeType==D.Document.MIME_TYPE_DIR) check(target.mkdir()) else check(target.createNewFile())
    return id(target)
  }
  override fun deleteDocument(documentId:String) { check(file(documentId).deleteRecursively()) }
  override fun renameDocument(documentId:String,displayName:String):String { val target=File(file(documentId).parentFile,displayName); check(file(documentId).renameTo(target)); return id(target) }
  override fun isChildDocument(parentDocumentId:String,documentId:String):Boolean = file(documentId).canonicalPath.startsWith(file(parentDocumentId).canonicalPath+File.separator)
}
