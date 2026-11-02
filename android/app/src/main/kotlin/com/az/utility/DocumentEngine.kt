package com.az.utility

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract as D
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/** Streaming provider operations. No conversion of a content URI to a file path. */
class DocumentEngine(private val activity: Activity) {
  private val resolver get() = activity.contentResolver
  private val thumbnails=Executors.newFixedThreadPool(2)
  private val worker = Executors.newSingleThreadExecutor()
  private val main = Handler(Looper.getMainLooper())
  private val cancelled = AtomicBoolean(false)
  private val busy = AtomicBoolean(false)
  @Volatile private var progress: Map<String, Any?> = mapOf("files" to 0)
  private var signal=android.os.CancellationSignal()
  private val active=java.util.Collections.synchronizedSet(mutableSetOf<java.io.Closeable>())
  private val directory = D.Document.MIME_TYPE_DIR
  fun stop() {
    cancelled.set(true); signal.cancel()
    val streams=synchronized(active) { active.toList() }
    for(stream in streams) try { stream.close() } catch(_:Exception) {}
  }
  fun close() { stop(); worker.shutdownNow(); thumbnails.shutdownNow() }
  private fun check() { check(!cancelled.get() && !Thread.currentThread().isInterrupted) { "Operation cancelled" } }
  private fun document(uri: Uri): Uri = if (D.isDocumentUri(activity,uri)) uri else D.buildDocumentUriUsingTree(uri,D.getTreeDocumentId(uri))
  private fun name(value: String): String {
    require(value.isNotBlank() && value != "." && value != ".." && value.none { it == '/' || it == '\\' || it == '\u0000' }) { "Invalid document name" }
    return value
  }
  fun children(uri: Uri): List<Map<String,Any?>> {
    val parent=document(uri)
    val target=D.buildChildDocumentsUriUsingTree(parent,D.getDocumentId(parent))
    val out=mutableListOf<Map<String,Any?>>()
    resolver.query(target,arrayOf(D.Document.COLUMN_DOCUMENT_ID,D.Document.COLUMN_DISPLAY_NAME,D.Document.COLUMN_MIME_TYPE,D.Document.COLUMN_SIZE,D.Document.COLUMN_LAST_MODIFIED),null,null,null,signal)?.use { c ->
      while(c.moveToNext()) {
        check(); require(out.size<10000) { "Folder exceeds 10,000 entries; narrow your selection" }
        out.add(mapOf("uri" to D.buildDocumentUriUsingTree(parent,c.getString(0)).toString(),"name" to c.getString(1),"mime" to c.getString(2),"size" to if(c.isNull(3)) -1L else c.getLong(3),"modified" to c.getLong(4)))
      }
    } ?: error("Provider returned no cursor")
    return out
  }
  private fun metadata(uri: Uri): Map<String,Any?> {
    resolver.query(uri,arrayOf(D.Document.COLUMN_DISPLAY_NAME,D.Document.COLUMN_MIME_TYPE,D.Document.COLUMN_SIZE,D.Document.COLUMN_LAST_MODIFIED),null,null,null,signal)?.use { c ->
      check(c.moveToFirst()) { "Document no longer exists" }
      return mapOf("uri" to uri.toString(),"name" to c.getString(0),"mime" to c.getString(1),"size" to if(c.isNull(2)) -1L else c.getLong(2),"modified" to c.getLong(3))
    }
    error("Document unavailable")
  }
  private fun input(uri: Uri): InputStream {
    val stream=object:java.io.FilterInputStream(resolver.openInputStream(uri) ?: error("Cannot open document")) { override fun close() { try { super.close() } finally { active.remove(this) } } }
    active.add(stream); return stream
  }
  private fun output(uri: Uri): OutputStream {
    val stream=object:java.io.FilterOutputStream(resolver.openOutputStream(uri,"w") ?: error("Cannot write document")) { override fun close() { try { super.close() } finally { active.remove(this) } }; override fun write(b:ByteArray,off:Int,len:Int) { out.write(b,off,len) } }
    active.add(stream); return stream
  }
  private fun create(parent: Uri, filename: String, mime: String): Uri {
    val valid=name(filename)
    require(children(parent).none { it["name"] == valid }) { "Destination exists; overwriting is disabled" }
    val created=D.createDocument(resolver,document(parent),mime,valid) ?: error("Provider refused creation")
    if (metadata(created)["name"] != valid) { D.deleteDocument(resolver,created); error("Provider changed destination name; operation stopped") }
    return created
  }
  private fun transfer(input: InputStream, output: OutputStream, limit: Long=Long.MAX_VALUE): Long {
    val buffer=ByteArray(65536); var size=0L
    while(true) { check(); val n=input.read(buffer); if(n<0) break; size+=n; require(size<=limit) { "Transfer exceeds expansion limit" }; output.write(buffer,0,n) }
    return size
  }
  private fun scan(root: Uri, exclusions: Set<String>): List<Map<String,Any?>> {
    val pending=java.util.ArrayDeque<Uri>(); pending.add(document(root)); val seen=mutableSetOf<String>()
    val files=mutableListOf<Map<String,Any?>>()
    var total=0L; var errors=0
    while(pending.isNotEmpty()) {
      check(); val parent=pending.removeLast(); if(!seen.add(parent.toString())) continue
      try {
        for(row in children(parent)) {
          check(); if(row["name"] in exclusions) continue
          if(row["mime"] == directory) { require(pending.size<10000) { "Directory queue limit reached" }; pending.add(Uri.parse(row["uri"] as String)) }
          else { require(files.size<100000) { "100,000-file limit reached; choose a smaller folder" }; files.add(row); total+=(row["size"] as Number).toLong().coerceAtLeast(0) }
          progress=mapOf("files" to files.size,"bytes" to total,"location" to row["name"],"errors" to errors)
        }
      } catch(e:SecurityException) { errors++ } catch(e:java.io.FileNotFoundException) { errors++ }
    }
    progress=progress + mapOf("errors" to errors)
    return files
  }
  private fun duplicates(files: List<Map<String,Any?>>): List<List<Map<String,Any?>>> {
    val candidates=files.groupBy { (it["size"] as Number).toLong() }.filter { it.key>0 && it.value.size>1 }.values.flatten()
    val hashes=mutableMapOf<String,MutableList<Map<String,Any?>>>()
    for((i,row) in candidates.withIndex()) {
      check(); val uri=Uri.parse(row["uri"] as String)
      try {
        val before=metadata(uri); val digest=MessageDigest.getInstance("SHA-256")
        input(uri).use { stream -> val b=ByteArray(65536); while(true) { check(); val n=stream.read(b); if(n<0) break; digest.update(b,0,n) } }
        val after=metadata(uri)
        if(before["size"] == row["size"] && before["modified"] == after["modified"] && before["size"] == after["size"]) {
          val hash=digest.digest().joinToString("") { "%02x".format(it) }
          hashes.getOrPut("${row["size"]}:$hash") { mutableListOf() }.add(row)
        }
      } catch(e:java.io.FileNotFoundException) { /* changed document */ }
      progress=mapOf("files" to i+1,"candidates" to candidates.size)
    }
    return hashes.values.filter { it.size>1 }
  }
  private fun copy(source: Uri, parent: Uri, count: IntArray, depth: Int=0): Uri {
    check(); require(depth<64 && ++count[0]<=100000) { "Copy tree limit exceeded" }
    val info=metadata(source)
    val target=create(parent,info["name"] as String,info["mime"] as String)
    try {
      if(info["mime"] == directory) {
        for(row in children(source)) copy(Uri.parse(row["uri"] as String),target,count,depth+1)
      } else {
        val written=input(source).use { i -> output(target).use { o -> transfer(i,o) } }
        val after=metadata(source)
        require(info["modified"] == after["modified"] && info["size"] == after["size"] && ((after["size"] as Number).toLong()<0 || written == (after["size"] as Number).toLong())) { "Source changed during copy; source retained" }
      }
      progress=mapOf("files" to count[0],"location" to info["name"])
      return target
    } catch(e:Exception) { try { D.deleteDocument(resolver,target) } catch(_:Exception) {}; throw e }
  }
  private fun zip(root: Uri, selected: List<String>, filename: String): String {
    val target=create(root,filename,"application/zip"); var expanded=0L; var entries=0
    fun add(zip: ZipOutputStream, uri: Uri, prefix: String, depth: Int) {
      check(); require(depth<64 && ++entries<=10000) { "Archive entry/depth limit exceeded" }
      val info=metadata(uri); val entry=prefix+name(info["name"] as String)
      if(info["mime"] == directory) { zip.putNextEntry(ZipEntry("$entry/")); zip.closeEntry(); for(row in children(uri)) add(zip,Uri.parse(row["uri"] as String),"$entry/",depth+1) }
      else { zip.putNextEntry(ZipEntry(entry)); expanded+=input(uri).use { transfer(it,zip,512L*1024*1024-expanded) }; zip.closeEntry() }
      progress=mapOf("files" to entries,"bytes" to expanded)
    }
    try { output(target).use { o -> ZipOutputStream(o).use { z -> for(s in selected) add(z,Uri.parse(s),"",0) } }; return target.toString() }
    catch(e:Exception) { try { D.deleteDocument(resolver,target) } catch(_:Exception) {}; throw e }
  }
  private fun unzip(source: Uri, parent: Uri, folder: String): String {
    val target=create(parent,folder,directory)
    val folders=mutableMapOf("" to target); val names=mutableSetOf<String>(); var expanded=0L; var count=0
    try {
      input(source).use { raw -> ZipInputStream(raw).use { zip ->
        while(true) {
          check(); val entry=zip.nextEntry ?: break
          require(++count<=10000) { "Archive exceeds 10,000 entries" }
          require(!entry.name.startsWith('/') && !entry.name.contains('\\') && !entry.name.contains(':')) { "Unsafe ZIP path" }
          val parts=entry.name.trimEnd('/').split('/'); require(parts.size<=64); parts.forEach { name(it) }
          val full=parts.joinToString("/"); require(names.add(full)) { "Duplicate ZIP entry" }
          var path=""; var destination=target
          for(part in parts.dropLast(1)) { path=if(path.isEmpty()) part else "$path/$part"; destination=folders.getOrPut(path) { create(destination,part,directory) } }
          if(entry.isDirectory) { if(!folders.containsKey(full)) folders[full]=create(destination,parts.last(),directory) }
          else {
            require(entry.size<0 || entry.size<=512L*1024*1024-expanded) { "Archive expansion limit" }
            val file=create(destination,parts.last(),"application/octet-stream")
            expanded+=output(file).use { transfer(zip,it,512L*1024*1024-expanded) }
          }
          zip.closeEntry(); progress=mapOf("files" to count,"bytes" to expanded)
        }
      } }
      return target.toString()
    } catch(e:Exception) { try { D.deleteDocument(resolver,target) } catch(_:Exception) {}; throw e }
  }
  fun media(): List<Map<String,Any?>> {
    val rows=mutableListOf<Map<String,Any?>>()
    for((collection,kind) in listOf(MediaStore.Images.Media.EXTERNAL_CONTENT_URI to "Images",MediaStore.Video.Media.EXTERNAL_CONTENT_URI to "Videos",MediaStore.Audio.Media.EXTERNAL_CONTENT_URI to "Audio")) {
      try { resolver.query(collection,arrayOf("_id","_display_name","mime_type","_size","date_modified"),null,null,"date_modified DESC")?.use { c ->
        while(c.moveToNext() && rows.size<10000) rows.add(mapOf("uri" to android.content.ContentUris.withAppendedId(collection,c.getLong(0)).toString(),"name" to c.getString(1),"mime" to c.getString(2),"size" to if(c.isNull(3)) -1L else c.getLong(3),"modified" to c.getLong(4)*1000,"category" to kind))
      } } catch(_:SecurityException) { /* Permission may cover selected visual media only. */ }
    }
    return rows
  }
  fun handle(call: MethodCall,result: MethodChannel.Result): Boolean {
    if(call.method=="thumbnail") {
      thumbnails.execute {
        try {
          val bytes=if(android.os.Build.VERSION.SDK_INT>=29) {
            val image=resolver.loadThumbnail(Uri.parse(call.argument<String>("uri")!!),android.util.Size(96,96),null)
            try { java.io.ByteArrayOutputStream().use { output -> image.compress(android.graphics.Bitmap.CompressFormat.PNG,90,output); output.toByteArray() } } finally { image.recycle() }
          } else null
          main.post { result.success(bytes) }
        } catch(_:Exception) { main.post { result.success(null) } }
      }
      return true
    }
    if(call.method=="documentProgress") { result.success(progress); return true }
    if(call.method=="cancelDocuments") { stop(); result.success(null); return true }
    if(call.method=="safShare") {
      val uri=Uri.parse(call.argument<String>("uri")!!)
      val intent=Intent(Intent.ACTION_SEND).setType(call.argument<String>("mime") ?: "application/octet-stream").putExtra(Intent.EXTRA_STREAM,uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      intent.clipData=android.content.ClipData.newRawUri("Shared document",uri)
      activity.startActivity(Intent.createChooser(intent,"Share document")); result.success(null); return true
    }
    if(call.method !in setOf("documentScan","documentDuplicates","documentCopy","documentZip","documentExtract","documentInspect","listMedia")) return false
    if(!busy.compareAndSet(false,true)) { result.error("BUSY","Another document operation is active",null); return true }
    cancelled.set(false); signal=android.os.CancellationSignal(); progress=mapOf("files" to 0)
    worker.execute {
      try {
        val uri=call.argument<String>("uri")?.let { Uri.parse(it) }
        val value: Any?=when(call.method) {
          "listMedia" -> media()
          "documentScan" -> scan(uri!!,(call.argument<List<String>>("exclusions") ?: emptyList()).toSet())
          "documentDuplicates" -> duplicates(scan(uri!!,(call.argument<List<String>>("exclusions") ?: emptyList()).toSet()))
          "documentCopy" -> {
            val parent=document(Uri.parse(call.argument<String>("destination")!!)); val source=document(uri!!)
            val isDirectory=metadata(source)["mime"]==directory
            require(source != parent && !(isDirectory && source.authority==parent.authority && D.isChildDocument(resolver,source,parent))) { "Cannot copy into the source tree" }
            val moving=call.argument<Boolean>("move")==true
            val before=if(moving && isDirectory) scan(source,emptySet()).associate { it["uri"] to listOf(it["size"],it["modified"]) } else null
            val copied=copy(source,parent,intArrayOf(0))
            check()
            if(before!=null) require(before==scan(source,emptySet()).associate { it["uri"] to listOf(it["size"],it["modified"]) }) { "Source tree changed; source and completed copy retained" }
            if(moving) check(D.deleteDocument(resolver,source)) { "Copy succeeded, but source removal failed" }
            copied.toString()
          }
          "documentZip" -> zip(uri!!,call.argument<List<String>>("selected")!!,call.argument<String>("name")!!)
          "documentExtract" -> unzip(uri!!,Uri.parse(call.argument<String>("destination")!!),call.argument<String>("name")!!)
          else -> {
            val entries=mutableListOf<String>(); var size=0L
            input(uri!!).use { raw -> ZipInputStream(raw).use { z -> while(true) { check(); val e=z.nextEntry ?: break; require(entries.size<10000); entries.add(e.name); size+=transfer(z,object:OutputStream(){ override fun write(b:Int) {} ; override fun write(b:ByteArray,off:Int,len:Int) {} },512L*1024*1024-size); z.closeEntry(); progress=mapOf("files" to entries.size,"bytes" to size) } } }; entries
          }
        }
        main.post { result.success(value) }
      } catch(e:Exception) { main.post { result.error("DOCUMENT",e.message,null) } }
      finally { busy.set(false) }
    }
    return true
  }
}
