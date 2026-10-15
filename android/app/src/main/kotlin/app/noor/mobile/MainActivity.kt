package app.noor.mobile

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import com.frostwire.jlibtorrent.AnnounceEntry
import com.frostwire.jlibtorrent.AlertListener
import com.frostwire.jlibtorrent.Priority
import com.frostwire.jlibtorrent.SessionManager
import com.frostwire.jlibtorrent.SessionParams
import com.frostwire.jlibtorrent.SettingsPack
import com.frostwire.jlibtorrent.Sha1Hash
import com.frostwire.jlibtorrent.TorrentFlags
import com.frostwire.jlibtorrent.TorrentHandle
import com.frostwire.jlibtorrent.TorrentInfo
import com.frostwire.jlibtorrent.TorrentStatus
import com.frostwire.jlibtorrent.alerts.Alert
import com.frostwire.jlibtorrent.alerts.AlertType
import com.frostwire.jlibtorrent.alerts.TorrentRemovedAlert
import com.frostwire.jlibtorrent.swig.add_torrent_params
import com.frostwire.jlibtorrent.swig.error_code
import com.frostwire.jlibtorrent.swig.session_handle
import com.frostwire.jlibtorrent.swig.settings_pack
import java.net.URLDecoder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Collections
import java.util.LinkedHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

private const val TAG = "NoorTorrent"
private const val METHOD_CHANNEL = "noor/torrent"
private const val EVENT_CHANNEL = "noor/torrent/events"
private const val LINK_CHANNEL = "noor/links"

/** Host of the registered Trakt OAuth HTTPS redirect (App Links return). */
private const val TRAKT_LINK_HOST =
    "preview-chat-607a5306-ab5d-4ec1-9d61-23b1874d8c08.space-z.ai"

/**
 * App-identifier private-use scheme (RFC 8252) used as the OAuth return for
 * AniList / MyAnimeList: `app.noor.mobile://callback?code=…&state=…`.
 */
private const val OAUTH_SCHEME = "app.noor.mobile"

/** Per-attempt budget for the staged metadata fetch (see resolveMetadata). */
private const val RESOLVE_ATTEMPT_SECONDS = 22
private const val RESOLVE_RETRY_SECONDS = 26

/** Total budget actually reported to the user in the timeout message. */
private const val RESOLVE_TOTAL_SECONDS = RESOLVE_ATTEMPT_SECONDS + RESOLVE_RETRY_SECONDS

/** How long to wait for the torrent handle to appear after an async add. */
private const val HANDLE_WAIT_MS = 15_000L

/** `tr=` / `tr[]=` entries of a magnet URI (opaque URIs — Uri.getQueryParameters throws). */
private val MAGNET_TRACKER_REGEX = Regex("(?:^|&)(?:tr|tr\\[\\])=([^&]+)")

/** How long to wait for the swarm to deliver metadata after starting a download. */
private const val METADATA_WAIT_MS = 30_000L

/** EventChannel broadcast rate (~2 events per second). */
private const val EVENT_INTERVAL_MS = 500L

/** Port range offered to libtorrent for the listen socket (UPnP/NAT-PMP mapped). */
private const val LISTEN_INTERFACES = "0.0.0.0:6881-6889,[::]:6881-6889"

private const val DHT_BOOTSTRAP_NODES =
    "dht.libtorrent.org:25401,router.bittorrent.com:6881," +
        "dht.transmissionbt.com:6881,router.utorrent.com:6881"

/**
 * Typed error carrying a stable code across the platform channel boundary so
 * Dart can map it onto [PlatformException.code].
 */
private class TorrentEngineException(val code: String, message: String) : Exception(message)

/**
 * Immutable snapshot of the active (last started) streaming torrent, read by
 * the periodic status pump. Guarded by [MainActivity.activeLock].
 */
private class ActiveTorrent(
    val handle: TorrentHandle,
    val infoHash: String,
    val filePath: String,
    val fileSize: Long,
    /** Piece indices whose completion means the stream is ready to start. */
    val readyPieces: IntArray,
)

/**
 * Hosts the on-device torrent engine (FrostWire jlibtorrent / libtorrent
 * rasterbar) behind two Flutter channels:
 *
 *  - MethodChannel "noor/torrent": resolve / start / pause / resume / remove / stop
 *  - EventChannel "noor/torrent/events": throttled status broadcast for the
 *    ACTIVE torrent (the last one started).
 *
 * The engine itself is started lazily on first use so that app cold-start is
 * never delayed, and is shut down through the `stop` method call.
 */
class MainActivity :
    FlutterActivity(),
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newCachedThreadPool { r -> Thread(r, "noor-torrent-ops") }

    private val sessionLock = Any()
    private val activeLock = Any()
    private val eventLock = Any()

    @Volatile
    private var manager: SessionManager? = null

    /**
     * Raw bencoded torrent bytes keyed by lowercase-hex info-hash (Task 129).
     * Filled by [resolveMetadata] and [resolveTorrentData] so [startTorrent]
     * can add the torrent WITH metadata (`download(TorrentInfo, dir)`) instead
     * of re-fetching it from the swarm — on marginal mobile networks that
     * second fetch was a second chance to time out. Bounded LRU; also
     * invalidated on remove/stop.
     */
    private val torrentDataCache =
        Collections.synchronizedMap(object : LinkedHashMap<String, ByteArray>(8, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, ByteArray>?): Boolean =
                size > 8
        })

    @Volatile
    private var active: ActiveTorrent? = null

    private var eventSink: EventChannel.EventSink? = null
    private var eventExecutor: ScheduledExecutorService? = null
    private var pumpFuture: ScheduledFuture<*>? = null

    /** Dart-side listener for incoming magnet links (noor/links). */
    private var linkSink: EventChannel.EventSink? = null

    /** Magnet link captured before Flutter attached (cold-start VIEW intent). */
    @Volatile
    private var pendingLink: String? = null

    /** Clears the active torrent if libtorrent reports it removed. */
    private val sessionListener = object : AlertListener {
        override fun types(): IntArray = intArrayOf(
            AlertType.TORRENT_REMOVED.swig(),
            AlertType.TORRENT_ERROR.swig(),
        )

        override fun alert(alert: Alert<*>) {
            try {
                when (alert.type()) {
                    AlertType.TORRENT_REMOVED -> {
                        val hash = (alert as TorrentRemovedAlert).infoHash().toHex()
                        synchronized(activeLock) {
                            if (active?.infoHash == hash) active = null
                        }
                    }
                    AlertType.TORRENT_ERROR -> {
                        Log.w(TAG, "torrent error: ${alert.message()}")
                    }
                    else -> Unit
                }
            } catch (t: Throwable) {
                Log.w(TAG, "alert handling failed", t)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
        EventChannel(messenger, LINK_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    synchronized(eventLock) {
                        linkSink = events
                        // Deliver a magnet link captured before Flutter was ready.
                        pendingLink?.let { link ->
                            pendingLink = null
                            events.success(link)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    synchronized(eventLock) { linkSink = null }
                }
            },
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureLink(intent)
    }

    /** Emits a magnet / noor:// / app.noor.mobile:// / Trakt HTTPS ACTION_VIEW link to Dart, or parks it. */
    private fun captureLink(intent: Intent?) {
        val link = intent?.takeIf { it.action == Intent.ACTION_VIEW }?.dataString ?: return
        // magnet: → torrent flow; noor://callback → legacy Trakt OAuth return;
        // app.noor.mobile://callback?code=… → AniList / MyAnimeList OAuth return;
        // https://<registered redirect host>/?code=… → primary Trakt return
        // (Android App Links / browser redirect).
        val isTraktHttpsReturn = link.startsWith("https://", ignoreCase = true) &&
            runCatching {
                Uri.parse(link).host?.equals(TRAKT_LINK_HOST, ignoreCase = true) == true
            }.getOrDefault(false)
        if (!link.startsWith("magnet:", ignoreCase = true) &&
            !link.startsWith("noor:", ignoreCase = true) &&
            !link.startsWith("$OAUTH_SCHEME:", ignoreCase = true) &&
            !isTraktHttpsReturn
        ) {
            return
        }
        synchronized(eventLock) {
            val sink = linkSink
            if (sink != null) {
                runOnUiThread { sink.success(link) }
            } else {
                pendingLink = link
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        synchronized(eventLock) {
            eventSink = null
            linkSink = null
        }
        stopEventPump()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // ------------------------------------------------------------------ //
    //  MethodChannel "noor/torrent"
    // ------------------------------------------------------------------ //

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isSupported" -> result.success(true)
                "warmup" -> runAsync(result) {
                    // Pre-boot the libtorrent session (DHT bootstrap takes
                    // 10-30s on cold mobile networks) so the first real
                    // resolve does not pay that cost inside its own timeout.
                    ensureSession()
                    true
                }
                "resolve" -> {
                    val magnet = call.argument<String>("magnet")
                        ?: throw TorrentEngineException("invalid_args", "magnet is required")
                    runAsync(result) { resolveMetadata(magnet) }
                }
                "resolveTorrentData" -> {
                    // Task 129: P2P-free metadata bootstrap — Dart fetched the
                    // raw .torrent file from a public HTTP cache; decode it
                    // here (and cache the bytes so `start` never re-fetches
                    // metadata from the swarm).
                    val dataB64 = call.argument<String>("data")
                        ?: throw TorrentEngineException("invalid_args", "data is required")
                    runAsync(result) { resolveTorrentData(dataB64) }
                }
                "start" -> {
                    val magnet = call.argument<String>("magnet")
                        ?: throw TorrentEngineException("invalid_args", "magnet is required")
                    val fileIndex = call.argument<Int>("fileIndex")
                        ?: throw TorrentEngineException("invalid_args", "fileIndex is required")
                    val saveDir = call.argument<String>("saveDir")
                        ?: throw TorrentEngineException("invalid_args", "saveDir is required")
                    val sequential = call.argument<Boolean>("sequential") ?: true
                    runAsync(result) { startTorrent(magnet, fileIndex, saveDir, sequential) }
                }
                "pause" -> {
                    val infoHash = requireHash(call)
                    runAsync(result) {
                        pauseOrResume(infoHash, pause = true)
                        true
                    }
                }
                "resume" -> {
                    val infoHash = requireHash(call)
                    runAsync(result) {
                        pauseOrResume(infoHash, pause = false)
                        true
                    }
                }
                "remove" -> {
                    val infoHash = requireHash(call)
                    val deleteFiles = call.argument<Boolean>("deleteFiles") ?: false
                    runAsync(result) {
                        removeTorrent(infoHash, deleteFiles)
                        true
                    }
                }
                "stop" -> runAsync(result) {
                    stopEngine()
                    true
                }
                else -> result.notImplemented()
            }
        } catch (e: TorrentEngineException) {
            result.error(e.code, e.message, null)
        } catch (t: Throwable) {
            Log.e(TAG, "method ${call.method} failed", t)
            // Task 127: include the real exception class — a bare `t.message`
            // (e.g. an obfuscated class name like "g0.d") is undiagnosable.
            result.error(
                "torrent_error",
                "${t.javaClass.name}: ${t.message ?: "torrent operation failed"}",
                null,
            )
        }
    }

    private fun requireHash(call: MethodCall): String =
        call.argument<String>("infoHash")
            ?: throw TorrentEngineException("invalid_args", "infoHash is required")

    /** Runs [block] on a worker thread and always answers on the main thread. */
    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: TorrentEngineException) {
                mainHandler.post { result.error(e.code, e.message, null) }
            } catch (t: Throwable) {
                Log.e(TAG, "torrent operation failed", t)
                mainHandler.post {
                    // Task 127: include the real exception class for diagnosis.
                    result.error(
                        "torrent_error",
                        "${t.javaClass.name}: ${t.message ?: "torrent operation failed"}",
                        null,
                    )
                }
            }
        }
    }

    // ------------------------------------------------------------------ //
    //  Engine operations
    // ------------------------------------------------------------------ //

    /**
     * Starts (or reuses) the libtorrent session with DHT, LSD and UPnP/NAT-PMP
     * enabled, both uTP and TCP transports, and an automatic listen port inside
     * 6881-6889. Anonymous mode is explicitly OFF so public swarms perform well.
     */
    private fun ensureSession(): SessionManager {
        synchronized(sessionLock) {
            manager?.let { return it }

            val sm = SessionManager()
            sm.addListener(sessionListener)

            val sp = SettingsPack()
            sp.listenInterfaces(LISTEN_INTERFACES)
            sp.enableDht(true)
            sp.setString(settings_pack.string_types.dht_bootstrap_nodes.swigValue(), DHT_BOOTSTRAP_NODES)
            sp.setBoolean(settings_pack.bool_types.enable_lsd.swigValue(), true)
            sp.setBoolean(settings_pack.bool_types.enable_upnp.swigValue(), true)
            sp.setBoolean(settings_pack.bool_types.enable_natpmp.swigValue(), true)
            sp.setBoolean(settings_pack.bool_types.enable_outgoing_tcp.swigValue(), true)
            sp.setBoolean(settings_pack.bool_types.enable_incoming_tcp.swigValue(), true)
            sp.setBoolean(settings_pack.bool_types.enable_outgoing_utp.swigValue(), true)
            sp.setBoolean(settings_pack.bool_types.enable_incoming_utp.swigValue(), true)
            // Announce through every tracker instead of a single winner.
            sp.setBoolean(settings_pack.bool_types.announce_to_all_trackers.swigValue(), true)
            sp.setBoolean(settings_pack.bool_types.announce_to_all_tiers.swigValue(), true)
            sp.anonymousMode(false)
            // Keep the phone light: one streaming download plus a couple of
            // background seeds is all this app needs.
            sp.activeDownloads(2)
            sp.activeSeeds(2)
            sp.connectionsLimit(180)

            sm.start(SessionParams(sp))
            manager = sm
            Log.i(TAG, "libtorrent session started (dht=${sm.isDhtRunning()})")
            return sm
        }
    }

    /**
     * Fetches metadata for [magnet] with a STAGED retry: the first attempt
     * doubles as the DHT bootstrap warm-up (a cold session usually cannot
     * beat even a 30s window on UDP-restricted mobile networks), and the
     * second attempt rides the now-bootstrapped DHT + tracker announces.
     * On timeout the temp metadata-only torrent is removed internally by
     * jlibtorrent, so no manual cleanup is required here.
     */
    private fun resolveMetadata(magnet: String): Map<String, Any> {
        val sm = ensureSession()
        val data: ByteArray? = sm.fetchMagnet(magnet, RESOLVE_ATTEMPT_SECONDS)
            ?: run {
                Log.i(
                    TAG,
                    "metadata attempt 1 timed out after ${RESOLVE_ATTEMPT_SECONDS}s — retrying on the warmed session",
                )
                sm.fetchMagnet(magnet, RESOLVE_RETRY_SECONDS)
            }
            ?: throw TorrentEngineException(
                "metadata_timeout",
                "Timed out fetching torrent metadata after ${RESOLVE_TOTAL_SECONDS}s",
            )
        val ti = TorrentInfo.bdecode(data)
        if (!ti.isValid()) {
            throw TorrentEngineException("invalid_metadata", "Decoded torrent metadata is not valid")
        }
        stashTorrentData(ti.infoHash().toHex(), data)
        return metadataFromTorrentInfo(ti)
    }

    /**
     * Task 129: decodes a raw .torrent file (base64) fetched by Dart from the
     * HTTP torrent cache — a P2P-free metadata bootstrap for networks where
     * the swarm is unreachable. The bytes are cached so the subsequent `start`
     * adds the torrent with metadata already in hand.
     */
    private fun resolveTorrentData(dataB64: String): Map<String, Any> {
        val bytes = try {
            Base64.decode(dataB64, Base64.DEFAULT)
        } catch (t: Throwable) {
            throw TorrentEngineException("invalid_metadata", "Torrent data is not valid base64: ${t.message}")
        }
        val ti = try {
            TorrentInfo.bdecode(bytes)
        } catch (t: Throwable) {
            throw TorrentEngineException("invalid_metadata", "Torrent data is not a bencoded torrent: ${t.message}")
        }
        if (!ti.isValid()) {
            throw TorrentEngineException("invalid_metadata", "Decoded torrent metadata is not valid")
        }
        stashTorrentData(ti.infoHash().toHex(), bytes)
        return metadataFromTorrentInfo(ti)
    }

    private fun metadataFromTorrentInfo(ti: TorrentInfo): Map<String, Any> {
        val files = ArrayList<Map<String, Any>>(ti.numFiles())
        val fs = ti.files()
        for (i in 0 until ti.numFiles()) {
            files.add(
                mapOf(
                    "index" to i,
                    "name" to fs.fileName(i),
                    "size" to fs.fileSize(i),
                ),
            )
        }
        return mapOf(
            "name" to ti.name(),
            "infoHash" to ti.infoHash().toHex(),
            "files" to files,
        )
    }

    private fun stashTorrentData(hashHex: String, bytes: ByteArray) {
        if (hashHex.isBlank() || bytes.isEmpty()) return
        try {
            torrentDataCache[hashHex] = bytes
        } catch (t: Throwable) {
            Log.w(TAG, "torrent data cache stash failed: ${t.message}")
        }
    }

    private fun cachedTorrentData(hashHex: String): ByteArray? =
        try {
            torrentDataCache[hashHex]
        } catch (t: Throwable) {
            Log.w(TAG, "torrent data cache read failed: ${t.message}")
            null
        }

    /**
     * Starts downloading [fileIndex] from [magnet] into [saveDir]. The target
     * file gets priority 4 while every other file is ignored (0); the first and
     * last pieces of the target file jump to priority 7 so containers open and
     * seek fast. Sequential download is enabled for smooth playback.
     */
    private fun startTorrent(
        magnet: String,
        fileIndex: Int,
        saveDir: String,
        sequential: Boolean,
    ): Map<String, String> {
        val sm = ensureSession()
        val dir = File(saveDir)
        if (!dir.exists() && !dir.mkdirs()) {
            throw TorrentEngineException("io_error", "Cannot create save directory: $saveDir")
        }

        val hashHex = infoHashOf(magnet)
        // Task 129: add the torrent WITH metadata when we already have the
        // raw bytes (from resolveMetadata / resolveTorrentData) — the old
        // path re-added from the magnet and waited for the swarm AGAIN inside
        // awaitMetadata (a second 30s timeout window on marginal networks).
        val cached = cachedTorrentData(hashHex)
        if (cached != null) {
            try {
                sm.download(TorrentInfo.bdecode(cached), dir)
            } catch (t: Throwable) {
                Log.w(TAG, "cached torrent data unusable (${t.message}) — falling back to magnet")
                sm.download(magnet, dir)
            }
        } else {
            sm.download(magnet, dir)
        }

        val th = awaitHandle(sm, hashHex)
            ?: throw TorrentEngineException(
                "torrent_start_failed",
                "Torrent handle did not appear within ${HANDLE_WAIT_MS / 1000}s",
            )
        // Task 132: a torrent added from cached .torrent bytes only carries
        // the announce entries embedded in that file — the public HTTP
        // caches ship torrents with an EMPTY announce-list (verified live),
        // so the handle would run on DHT alone. On networks that throttle
        // UDP/DHT that is exactly the "Torrentio never works" failure. The
        // magnet always carries the Dart-side tracker merge (stream sources
        // + verified defaults) — re-announce those onto the handle.
        mergeMagnetTrackers(th, magnet)
        if (sequential) {
            th.setFlags(TorrentFlags.SEQUENTIAL_DOWNLOAD, TorrentFlags.SEQUENTIAL_DOWNLOAD)
        }

        val ti = awaitMetadata(th)
            ?: throw TorrentEngineException(
                "metadata_timeout",
                "Timed out waiting for torrent metadata while starting download",
            )
        applyPriorities(th, ti, fileIndex)

        val fs = ti.files()
        val pieceLength = ti.pieceLength().toLong()
        val firstPiece: Int
        val lastPiece: Int
        if (pieceLength > 0 && fileIndex in 0 until ti.numFiles()) {
            firstPiece = (fs.fileOffset(fileIndex) / pieceLength).toInt()
            lastPiece = ((fs.fileOffset(fileIndex) + fs.fileSize(fileIndex) - 1) / pieceLength)
                .toInt()
                .coerceAtLeast(firstPiece)
        } else {
            firstPiece = 0
            lastPiece = 0
        }
        val readyPieces = linkedSetOf(firstPiece, minOf(firstPiece + 1, lastPiece)).toIntArray()

        val snapshot = ActiveTorrent(
            handle = th,
            infoHash = hashHex,
            filePath = File(dir, fs.filePath(fileIndex)).absolutePath,
            fileSize = if (fileIndex in 0 until ti.numFiles()) fs.fileSize(fileIndex) else 0L,
            readyPieces = readyPieces,
        )
        synchronized(activeLock) { active = snapshot }

        Log.i(TAG, "streaming torrent started: $hashHex file#$fileIndex")
        return mapOf("torrentId" to hashHex)
    }

    private fun pauseOrResume(infoHash: String, pause: Boolean) {
        val sm = manager ?: return
        val th = sm.find(Sha1Hash(infoHash)) ?: return
        if (pause) th.pause() else th.resume()
    }

    private fun removeTorrent(infoHash: String, deleteFiles: Boolean) {
        torrentDataCache.remove(infoHash.lowercase())
        synchronized(activeLock) {
            if (active?.infoHash == infoHash) active = null
        }
        val sm = manager ?: return
        val th = sm.find(Sha1Hash(infoHash)) ?: return
        if (deleteFiles) {
            sm.remove(th, session_handle.delete_files)
        } else {
            sm.remove(th)
        }
    }

    /** Shuts the whole engine down; used on app teardown. */
    private fun stopEngine() {
        torrentDataCache.clear()
        synchronized(activeLock) { active = null }
        val sm = synchronized(sessionLock) {
            val current = manager
            manager = null
            current
        } ?: return
        try {
            sm.stop()
            Log.i(TAG, "libtorrent session stopped")
        } catch (t: Throwable) {
            Log.w(TAG, "session stop failed", t)
        }
    }

    // ------------------------------------------------------------------ //
    //  Helpers
    // ------------------------------------------------------------------ //

    private fun infoHashOf(magnet: String): String {
        val ec = error_code()
        return try {
            val params = add_torrent_params.parse_magnet_uri(magnet, ec)
            if (ec.value() != 0) {
                throw TorrentEngineException("invalid_magnet", ec.message())
            }
            Sha1Hash(params.getInfo_hash()).toHex()
        } catch (e: TorrentEngineException) {
            throw e
        } catch (t: Throwable) {
            throw TorrentEngineException("invalid_magnet", "Could not parse magnet uri: ${t.message}")
        }
    }

    private fun awaitHandle(sm: SessionManager, hashHex: String): TorrentHandle? {
        val deadline = System.currentTimeMillis() + HANDLE_WAIT_MS
        while (System.currentTimeMillis() < deadline) {
            val th = sm.find(Sha1Hash(hashHex))
            if (th != null && th.isValid()) return th
            Thread.sleep(200)
        }
        return null
    }

    private fun awaitMetadata(th: TorrentHandle): TorrentInfo? {
        val deadline = System.currentTimeMillis() + METADATA_WAIT_MS
        while (System.currentTimeMillis() < deadline) {
            if (!th.isValid()) return null
            val ti = th.torrentFile()
            if (ti != null && ti.isValid()) return ti
            Thread.sleep(250)
        }
        return null
    }

    /**
     * Adds every `tr=` tracker of [magnet] to [th] that the handle does not
     * already announce to. Deduplicated, failures per-tracker non-fatal.
     */
    private fun mergeMagnetTrackers(th: TorrentHandle, magnet: String) {
        try {
            val existing = th.trackers().mapTo(HashSet()) { it.url() }
            var added = 0
            for (match in MAGNET_TRACKER_REGEX.findAll(magnet)) {
                val url = try {
                    URLDecoder.decode(match.groupValues[1], "UTF-8").trim()
                } catch (t: Throwable) {
                    continue
                }
                if (url.isEmpty() || !existing.add(url)) continue
                try {
                    th.addTracker(AnnounceEntry(url))
                    added++
                } catch (t: Throwable) {
                    Log.w(TAG, "addTracker failed for $url: ${t.message}")
                }
            }
            if (added > 0) {
                Log.i(TAG, "merged $added magnet tracker(s) onto the torrent handle")
            }
        } catch (t: Throwable) {
            Log.w(TAG, "tracker merge skipped: ${t.message}")
        }
    }

    /**
     * Target file priority 4, everything else ignored, first/last pieces of the
     * target file at priority 7 (container headers live at both ends).
     */
    private fun applyPriorities(th: TorrentHandle, ti: TorrentInfo, fileIndex: Int) {
        val fileCount = ti.numFiles()
        if (fileCount <= 0) return

        val priorities = Priority.array(Priority.IGNORE, fileCount)
        if (fileIndex in 0 until fileCount) {
            priorities[fileIndex] = Priority.FOUR
        }
        th.prioritizeFiles(priorities)

        val pieceLength = ti.pieceLength().toLong()
        if (pieceLength <= 0 || fileIndex !in 0 until fileCount) return
        val fs = ti.files()
        val first = (fs.fileOffset(fileIndex) / pieceLength).toInt()
        val last = ((fs.fileOffset(fileIndex) + fs.fileSize(fileIndex) - 1) / pieceLength).toInt()
        th.piecePriority(first, Priority.SEVEN)
        if (last > first) th.piecePriority(last, Priority.SEVEN)
    }

    // ------------------------------------------------------------------ //
    //  EventChannel "noor/torrent/events"
    // ------------------------------------------------------------------ //

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        synchronized(eventLock) { eventSink = events }
        startEventPump()
    }

    override fun onCancel(arguments: Any?) {
        synchronized(eventLock) { eventSink = null }
        stopEventPump()
    }

    private fun startEventPump() {
        synchronized(eventLock) {
            if (pumpFuture != null) return
            val exec = eventExecutor
                ?: Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "noor-torrent-events") }
                .also { eventExecutor = it }
            pumpFuture = exec.scheduleAtFixedRate(
                { emitStatus() },
                0,
                EVENT_INTERVAL_MS,
                TimeUnit.MILLISECONDS,
            )
        }
    }

    private fun stopEventPump() {
        synchronized(eventLock) {
            pumpFuture?.cancel(false)
            pumpFuture = null
        }
    }

    /** Builds one status snapshot for the ACTIVE torrent and broadcasts it. */
    private fun emitStatus() {
        val snapshot = synchronized(activeLock) { active } ?: return
        if (!snapshot.handle.isValid()) return
        try {
            val st = snapshot.handle.status(true)
            val paused = snapshot.handle.flags().and_(TorrentFlags.PAUSED).to_int() != 0
            val state = if (paused) "paused" else mapState(st.state())
            val wanted = st.totalWanted()
            val wantedDone = st.totalWantedDone()
            val progress = if (wanted > 0) {
                wantedDone.toDouble() / wanted.toDouble()
            } else {
                st.progress().toDouble()
            }
            val ready = snapshot.readyPieces.all { snapshot.handle.havePiece(it) }

            val event = mapOf<String, Any>(
                "infoHash" to snapshot.infoHash,
                "progress" to progress,
                "downloadRate" to st.downloadRate(),
                "uploadRate" to st.uploadRate(),
                "numPeers" to st.numPeers(),
                "numSeeds" to st.numSeeds(),
                "totalWanted" to wanted,
                "totalWantedDone" to wantedDone,
                "state" to state,
                "filePath" to snapshot.filePath,
                "fileSize" to snapshot.fileSize,
                "ready" to ready,
            )
            mainHandler.post {
                val sink = synchronized(eventLock) { eventSink } ?: return@post
                try {
                    sink.success(event)
                } catch (t: Throwable) {
                    Log.w(TAG, "event emit failed", t)
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "status poll failed", t)
        }
    }

    private fun mapState(state: TorrentStatus.State): String = when (state) {
        TorrentStatus.State.CHECKING_FILES,
        TorrentStatus.State.CHECKING_RESUME_DATA,
        TorrentStatus.State.ALLOCATING,
        -> "checking"
        TorrentStatus.State.FINISHED -> "finished"
        TorrentStatus.State.SEEDING -> "seeding"
        else -> "downloading"
    }
}
