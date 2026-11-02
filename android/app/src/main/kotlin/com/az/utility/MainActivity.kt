package com.az.utility

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.hardware.Sensor
import android.hardware.SensorManager
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
  private val documents by lazy { DocumentEngine(this) }
  private var permissionResult: MethodChannel.Result? = null
  private var sensorListener: android.hardware.SensorEventListener? = null
  private var sensorValues: List<Map<String,Any?>> = emptyList()
  private val handler = Handler(Looper.getMainLooper())
  private var treeResult: MethodChannel.Result? = null
  private var micResult: MethodChannel.Result? = null
  private var recorder: MediaRecorder? = null
  private var audioStop: Runnable? = null
  private var player: MediaPlayer? = null
  private var tone: ToneGenerator? = null
  private var recording: File? = null
  private var lastCpu = android.os.Process.getElapsedCpuTime()
  private var lastWall = android.os.SystemClock.elapsedRealtime()

  override fun configureFlutterEngine(engine: FlutterEngine) {
    super.configureFlutterEngine(engine)
    MethodChannel(engine.dartExecutor.binaryMessenger, "com.az.utility/native").setMethodCallHandler { call, result ->
      try {
        if(documents.handle(call,result)) return@setMethodCallHandler
        when(call.method) {
          "requestWifiPermission" -> {
            if(permissionResult!=null) result.error("BUSY","Permission request active",null)
            else { permissionResult=result; requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION),703) }
          }
          "requestMediaPermission" -> {
            if(permissionResult!=null) result.error("BUSY","Permission request active",null)
            else { permissionResult=result; val permissions=if(Build.VERSION.SDK_INT>=34) arrayOf(Manifest.permission.READ_MEDIA_IMAGES,Manifest.permission.READ_MEDIA_VIDEO,Manifest.permission.READ_MEDIA_AUDIO,Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) else if(Build.VERSION.SDK_INT>=33) arrayOf(Manifest.permission.READ_MEDIA_IMAGES,Manifest.permission.READ_MEDIA_VIDEO,Manifest.permission.READ_MEDIA_AUDIO) else arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE); requestPermissions(permissions,704) }
          }
          "startSensors" -> {
            stopSensors()
            val manager=getSystemService(Context.SENSOR_SERVICE) as SensorManager
            val latest=mutableMapOf<Int,Map<String,Any?>>()
            sensorListener=object:android.hardware.SensorEventListener {
              override fun onAccuracyChanged(sensor:Sensor?, accuracy:Int) {}
              override fun onSensorChanged(event:android.hardware.SensorEvent) {
                latest[event.sensor.type]=mapOf("name" to event.sensor.name,"type" to event.sensor.stringType,"values" to event.values.map { it.toDouble() },"accuracy" to event.accuracy,"timestampNanos" to event.timestamp)
                sensorValues=latest.values.toList()
              }
            }
            val supported=listOf(Sensor.TYPE_ACCELEROMETER,Sensor.TYPE_GYROSCOPE,Sensor.TYPE_LIGHT,Sensor.TYPE_PROXIMITY,Sensor.TYPE_MAGNETIC_FIELD).mapNotNull { manager.getDefaultSensor(it) }
            for(sensor in supported) manager.registerListener(sensorListener,sensor,SensorManager.SENSOR_DELAY_NORMAL)
            result.success(supported.map { it.name })
          }
          "sensorReadings" -> result.success(sensorValues)
          "stopSensors" -> { stopSensors(); result.success(null) }
          "snapshot" -> result.success(snapshot())
          "chooseTree" -> {
            if(treeResult != null) { result.error("BUSY","A folder picker is already open",null) }
            else { treeResult=result; startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION), 701) }
          }
          "listSaf" -> {
            val uri=Uri.parse(call.argument<String>("uri")!!)
            Thread {
              try { val rows=listSaf(uri); handler.post { result.success(rows) } }
              catch(e:Exception) { handler.post { result.error("STORAGE",e.message,null) } }
            }.start()
          }
          "safRename" -> result.success(DocumentsContract.renameDocument(contentResolver,Uri.parse(call.argument<String>("uri")!!),validName(call.argument<String>("name")!!))?.toString())
          "safDelete" -> result.success(DocumentsContract.deleteDocument(contentResolver,Uri.parse(call.argument<String>("uri")!!)))
          "safCreateFolder" -> { val uri=Uri.parse(call.argument<String>("uri")!!); val parent=if(DocumentsContract.isDocumentUri(this,uri)) uri else DocumentsContract.buildDocumentUriUsingTree(uri,DocumentsContract.getTreeDocumentId(uri)); result.success(DocumentsContract.createDocument(contentResolver,parent,DocumentsContract.Document.MIME_TYPE_DIR,validName(call.argument<String>("name")!!))?.toString()) }
          "shareFile" -> {
            val source=File(call.argument<String>("path")!!)
            require(source.isFile && source.length()<=512L*1024*1024) { "Select a regular file up to 512 MiB" }
            val folder=File(cacheDir,"shared").apply { mkdirs() }
            // Remove stale temporary shares only after a day, so receiving apps have time to read.
            folder.listFiles()?.filter { System.currentTimeMillis()-it.lastModified()>86400000 }?.forEach { it.deleteRecursively() }
            val session=File(folder,java.util.UUID.randomUUID().toString()).apply { mkdirs() }
            val destination=File(session,source.name)
            Thread {
              try {
                source.copyTo(destination)
                val uri=androidx.core.content.FileProvider.getUriForFile(this,"com.az.utility.files",destination)
                handler.post {
                  try {
                    val intent=Intent(Intent.ACTION_SEND).setType("application/octet-stream").putExtra(Intent.EXTRA_STREAM,uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    intent.clipData=android.content.ClipData.newRawUri("Shared file",uri)
                    startActivity(Intent.createChooser(intent,"Share file")); result.success("Share chooser opened")
                  } catch(e:Exception) { result.error("SHARE",e.message,null) }
                }
              } catch(e:Exception) { handler.post { result.error("SHARE",e.message,null) } }
            }.start()
          }
          "safOpen" -> { startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(Uri.parse(call.argument<String>("uri")!!),call.argument<String>("mime")).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)); result.success("Opened") }
          "sensors" -> { val manager=getSystemService(Context.SENSOR_SERVICE) as SensorManager; result.success(manager.getSensorList(Sensor.TYPE_ALL).map { "${it.name}: ${it.vendor} (${it.stringType})" }.joinToString("\n").ifEmpty { "Unsupported: no sensors reported" }) }
          "speaker" -> { tone?.release(); tone=ToneGenerator(AudioManager.STREAM_MUSIC,50); tone?.startTone(ToneGenerator.TONE_DTMF_5,1000); handler.postDelayed({ tone?.release(); tone=null },1200); result.success("Played a 1-second tone at 50% generator volume. Confirm audibility yourself.") }
          "vibrate" -> { val vibrator=getSystemService(Context.VIBRATOR_SERVICE) as Vibrator; if(!vibrator.hasVibrator()) result.success("Unsupported: no vibrator") else { if(Build.VERSION.SDK_INT>=26) vibrator.vibrate(VibrationEffect.createOneShot(300,VibrationEffect.DEFAULT_AMPLITUDE)) else vibrator.vibrate(300); result.success("Requested a 300 ms vibration; confirm by touch.") } }
          "cancelHardware" -> { documents.stop(); stopSensors(); cleanupAudio(); tone?.release(); tone=null; micResult?.success("Hardware test cancelled"); micResult=null; result.success(null) }
          "microphone" -> {
            if(micResult!=null) result.error("BUSY","Recording already active",null)
            else { micResult=result; if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED) requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO),702) else startMicrophone() }
          }
          else -> result.notImplemented()
        }
      } catch(e: Exception) { result.error("NATIVE",e.message,null) }
    }
  }
  private fun snapshot(): List<Map<String,Any?>> {
    val metrics=mutableListOf<Map<String,Any?>>()
    fun add(label:String,value:Any?,ratio:Double?=null,status:String="available") { metrics.add(mapOf("label" to label,"value" to value,"ratio" to ratio,"status" to status)) }
    val info=ActivityManager.MemoryInfo(); (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(info)
    add("System RAM used","${(info.totalMem-info.availMem)/1048576} / ${info.totalMem/1048576} MiB",(info.totalMem-info.availMem).toDouble()/info.totalMem)
    add("Available system RAM","${info.availMem/1048576} MiB")
    val fs=StatFs(filesDir.absolutePath)
    add("App storage volume used","${(fs.totalBytes-fs.availableBytes)/1073741824.0} GiB",(fs.totalBytes-fs.availableBytes).toDouble()/fs.totalBytes)
    add("Volume capacity / free","${fs.totalBytes/1073741824.0} / ${fs.availableBytes/1073741824.0} GiB")
    val battery=registerReceiver(null,android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    val level=battery?.getIntExtra(BatteryManager.EXTRA_LEVEL,-1) ?: -1; val scale=battery?.getIntExtra(BatteryManager.EXTRA_SCALE,100) ?: 100
    if(level>=0 && scale>0) add("Battery charge","${level*100/scale}%",level.toDouble()/scale) else add("Battery charge","Unavailable",status="temporarilyUnavailable")
    val temperature=battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE,Int.MIN_VALUE) ?: Int.MIN_VALUE
    if(temperature!=Int.MIN_VALUE) add("Battery temperature","${temperature/10.0} °C")
    val voltage=battery?.getIntExtra(BatteryManager.EXTRA_VOLTAGE,0) ?: 0
    if(voltage>0) add("Battery voltage","$voltage mV")
    val batteryStatus=when(battery?.getIntExtra(BatteryManager.EXTRA_STATUS,0)) { BatteryManager.BATTERY_STATUS_CHARGING -> "Charging"; BatteryManager.BATTERY_STATUS_DISCHARGING -> "Discharging"; BatteryManager.BATTERY_STATUS_FULL -> "Full"; BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "Not charging"; else -> "Unavailable" }
    val source=when(battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED,0)) { BatteryManager.BATTERY_PLUGGED_AC -> "AC"; BatteryManager.BATTERY_PLUGGED_USB -> "USB"; BatteryManager.BATTERY_PLUGGED_WIRELESS -> "Wireless"; 0 -> "Battery"; else -> "Other" }
    add("Battery status / source","$batteryStatus / $source")
    val health=when(battery?.getIntExtra(BatteryManager.EXTRA_HEALTH,0)) { BatteryManager.BATTERY_HEALTH_GOOD -> "Good"; BatteryManager.BATTERY_HEALTH_OVERHEAT -> "Overheated"; BatteryManager.BATTERY_HEALTH_DEAD -> "Dead"; BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "Over-voltage"; BatteryManager.BATTERY_HEALTH_COLD -> "Cold"; BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "Unspecified failure"; else -> "Unavailable" }
    add("Battery reported condition","$health (Android status; battery wear is not assessed)",status=if(health=="Unavailable") "temporarilyUnavailable" else "available")
    val cpu=android.os.Process.getElapsedCpuTime(); val wall=android.os.SystemClock.elapsedRealtime()
    if(wall>lastWall) add("AZ process CPU (one-core basis)","${((cpu-lastCpu)*100.0/(wall-lastWall))}%")
    lastCpu=cpu; lastWall=wall
    add("System CPU load","Unsupported by public Android API",status="unsupported")
    add("Memory pressure",if(info.lowMemory) "Warning: Android reports low memory" else "Good: Android low-memory flag is clear")
    add("Device","${Build.MANUFACTURER} ${Build.MODEL}"); add("Architecture",Build.SUPPORTED_ABIS.joinToString())
    val micGranted=checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED
    add("Microphone permission",if(micGranted) "Granted" else "Requested only for microphone test",status=if(micGranted) "available" else "permissionRequired")
    add("Document-provider access","${contentResolver.persistedUriPermissions.size} persisted folder grants")
    add("Display","${resources.displayMetrics.widthPixels} × ${resources.displayMetrics.heightPixels}")
    val manager=getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    val caps=manager.getNetworkCapabilities(manager.activeNetwork)
    val transport=when { caps==null -> "Disconnected"; caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)->"Wi-Fi"; caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)->"Cellular"; caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)->"Ethernet"; caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)->"VPN"; else->"Other" }
    add("Active network",transport)
    add("Internet validation",if(caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)==true) "Validated by Android" else "Not validated")
    val links=manager.getLinkProperties(manager.activeNetwork); add("Local IP",links?.linkAddresses?.joinToString { it.address.hostAddress ?: "" } ?: "Unavailable"); add("DNS servers",links?.dnsServers?.joinToString { it.hostAddress ?: "" } ?: "Unavailable")
    if(caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)==true) {
      val wifi=(applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager).connectionInfo
      add("Wi-Fi RSSI / link","${wifi.rssi} dBm / ${wifi.linkSpeed} Mbps"); add("Wi-Fi frequency","${wifi.frequency} MHz")
      val allowed=checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED
      val ssid=wifi.ssid; val bssid=wifi.bssid
      add("Wi-Fi SSID",if(allowed && ssid!="<unknown ssid>") ssid else "Grant precise location and enable Location services for identifiers",status=if(allowed && ssid!="<unknown ssid>") "available" else "permissionRequired")
      add("Wi-Fi BSSID",if(allowed && bssid!=null && bssid!="02:00:00:00:00:00") bssid else "Unavailable / redacted by Android",status=if(allowed && bssid!=null && bssid!="02:00:00:00:00:00") "available" else "permissionRequired")
    }
    return metrics
  }
  private fun validName(value:String):String {
    require(value.isNotBlank() && value!="." && value!=".." && value.none { it=='/' || it=='\\' || it=='\u0000' }) { "Invalid document name" }
    return value
  }
  private fun listSaf(uri:Uri): List<Map<String,Any?>> {
    val id=if(DocumentsContract.isDocumentUri(this,uri)) DocumentsContract.getDocumentId(uri) else DocumentsContract.getTreeDocumentId(uri)
    val children=DocumentsContract.buildChildDocumentsUriUsingTree(uri,id)
    val rows=mutableListOf<Map<String,Any?>>()
    contentResolver.query(children,arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,DocumentsContract.Document.COLUMN_DISPLAY_NAME,DocumentsContract.Document.COLUMN_MIME_TYPE,DocumentsContract.Document.COLUMN_SIZE,DocumentsContract.Document.COLUMN_LAST_MODIFIED),null,null,null)?.use { c ->
      while(c.moveToNext() && rows.size<10000) rows.add(mapOf("uri" to DocumentsContract.buildDocumentUriUsingTree(uri,c.getString(0)).toString(),"name" to c.getString(1),"mime" to c.getString(2),"size" to c.getLong(3),"modified" to c.getLong(4)))
    }
    return rows
  }
  override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?) {
    super.onActivityResult(requestCode,resultCode,data)
    if(requestCode==701) { val uri=data?.data; if(resultCode==Activity.RESULT_OK && uri!=null) { try { contentResolver.takePersistableUriPermission(uri,(data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)); treeResult?.success(uri.toString()) } catch(e:Exception) { treeResult?.error("PERMISSION",e.message,null) } } else treeResult?.success(null); treeResult=null }
  }
  override fun onRequestPermissionsResult(requestCode:Int,permissions:Array<out String>,grantResults:IntArray) {
    super.onRequestPermissionsResult(requestCode,permissions,grantResults)
    if((requestCode==703 || requestCode==704) && permissionResult!=null) { permissionResult?.success(if(grantResults.any { it==PackageManager.PERMISSION_GRANTED }) "Permission response received. Only granted data is shown." else "Permission denied. You can continue using other tools."); permissionResult=null }
    if(requestCode==702 && micResult!=null) { if(grantResults.firstOrNull()==PackageManager.PERMISSION_GRANTED) startMicrophone() else { micResult?.success("Permission required: microphone access was denied"); micResult=null } }
  }
  private fun startMicrophone() {
    try {
      recording=File(cacheDir,"az-microphone.m4a")
      recorder=(if(Build.VERSION.SDK_INT>=31) MediaRecorder(this) else MediaRecorder()).apply { setAudioSource(MediaRecorder.AudioSource.MIC); setOutputFormat(MediaRecorder.OutputFormat.MPEG_4); setAudioEncoder(MediaRecorder.AudioEncoder.AAC); setOutputFile(recording!!.absolutePath); prepare(); start() }
      audioStop=Runnable {
        try { recorder?.stop(); recorder?.release(); recorder=null; player=MediaPlayer().apply { setDataSource(recording!!.absolutePath); prepare(); setOnCompletionListener { cleanupAudio(); micResult?.success("Recorded and played back 3 seconds locally. Confirm audio quality yourself."); micResult=null }; start() } }
        catch(e:Exception) { cleanupAudio(); micResult?.error("AUDIO",e.message,null); micResult=null }
      }
      handler.postDelayed(audioStop!!,3000)
    } catch(e:Exception) { cleanupAudio(); micResult?.error("AUDIO",e.message,null); micResult=null }
  }
  private fun cleanupAudio() { audioStop?.let { handler.removeCallbacks(it) }; audioStop=null; recorder?.release(); recorder=null; player?.release(); player=null; recording?.delete(); recording=null }
  private fun stopSensors() { sensorListener?.let { (getSystemService(Context.SENSOR_SERVICE) as SensorManager).unregisterListener(it) }; sensorListener=null; sensorValues=emptyList() }
  override fun onPause() { super.onPause(); stopSensors(); handler.removeCallbacksAndMessages(null); cleanupAudio(); tone?.release(); tone=null; micResult?.success("Microphone test stopped because app left foreground"); micResult=null }
  override fun onDestroy() { documents.close(); stopSensors(); cleanupAudio(); super.onDestroy() }
}
