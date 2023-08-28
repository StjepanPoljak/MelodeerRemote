package com.melodeer.remote

import android.graphics.Color
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import android.view.View
import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.TextView
import android.widget.Button
import android.widget.ProgressBar

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo

import com.github.kittinunf.fuel.Fuel
import com.github.kittinunf.fuel.core.extensions.jsonBody

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.Serializable

@Serializable
class Path(val path: String, val type: String) {

	fun basename(): String {
		return this.path.substringAfterLast('/')
	}

	fun parent(): Path {
		return Path(this.path.substringBeforeLast('/'), "d")
	}

	override fun toString(): String {
		return this.path
	}
}

data class PathItem(val path: Path, var selected: Boolean)

data class CurrentState(var serviceInfo: NsdServiceInfo?, var currDir: Path?, var selectMode: Boolean, var error: Boolean)

@Serializable
data class MelodeerRequest(val comm: String, val list: ArrayList<Path>)

class PathItemAdapter(context: Context, resource: Int, private val pathItemList: List<PathItem>) :
	ArrayAdapter<PathItem>(context, resource, pathItemList) {

	override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
		val itemView = LayoutInflater.from(context).inflate(android.R.layout.simple_list_item_1, parent, false)

		val nameTextView: TextView = itemView.findViewById(android.R.id.text1)
		nameTextView.text = pathItemList[position].path.basename()
		itemView.setBackgroundColor(if (pathItemList[position].selected) Color.LTGRAY else Color.WHITE)

		return itemView
	}
}

@Serializable
data class MelodeerResponse(val status: String, val list: ArrayList<Path>, val chdir: Path)

class MainActivity : AppCompatActivity() {

	private lateinit var itemListView: ListView
	private lateinit var itemList: ArrayList<PathItem>
	private lateinit var playButton: Button
	private lateinit var stopButton: Button
	private lateinit var incVolButton: Button
	private lateinit var decVolButton: Button
	private lateinit var retryButton: Button
	private lateinit var greyOverlay: View

	private lateinit var adapter: PathItemAdapter
	private lateinit var nsdManager: NsdManager
	private lateinit var stateTextView: TextView
	private lateinit var progressBar: ProgressBar

	private var currentState: CurrentState = CurrentState(null, null, false, false)

	val resolveListener = object : NsdManager.ResolveListener {
		override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
			setStatus("Could not resolve ${serviceInfo.serviceName}.")
		}

		override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
			runOnUiThread {
				setStatus("Resolved ${serviceInfo.serviceName}: ${serviceInfo.host}:${serviceInfo.port}")
				currentState.serviceInfo = serviceInfo
				sendRequest(MelodeerRequest("enter", ArrayList()))
			}
		}
        }

	val discoveryListener = object : NsdManager.DiscoveryListener {

		override fun onDiscoveryStarted(regType: String) {
			setStatus("Discovering...")
        	}

		override fun onServiceFound(serviceInfo: NsdServiceInfo) {
			if (currentState.serviceInfo == null && serviceInfo.serviceName.startsWith("MelodeerService")) {
				nsdManager.resolveService(serviceInfo, resolveListener)
				endBlockingActivity()
			}
		}

		override fun onServiceLost(serviceInfo: NsdServiceInfo) {
			currentState.serviceInfo?.let {
				if (serviceInfo.serviceName == it.serviceName) {
					currentState.serviceInfo = null
				}
			}
			setStatus("Service lost: " + serviceInfo.serviceName)
		}

		override fun onDiscoveryStopped(serviceType: String) {
			setStatus("Discovery stopped.")
		}

		override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
			setStatus("Discovery failed to start.")
		}

		override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
			setStatus("Discovery failed to stop.")
		}
	}

	fun selectItem(pos: Int): Boolean {

		if (itemList[pos].path.type != "f") {
			return false
		}

		itemList[pos].selected = !itemList[pos].selected

		if (itemList.filter{ it.selected }.isEmpty()) {
			currentState.selectMode = false
		}

		return true
	}

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		setContentView(R.layout.activity_main)

		greyOverlay = findViewById(R.id.greyOverlay)
		progressBar = findViewById(R.id.progressBar)
		stateTextView = findViewById(R.id.stateTextView)
		itemListView = findViewById(R.id.itemListView)
		playButton = findViewById(R.id.playButton)
		stopButton = findViewById(R.id.stopButton)
		incVolButton = findViewById(R.id.incVolButton)
		decVolButton = findViewById(R.id.decVolButton)
		retryButton = findViewById(R.id.retryButton)

		itemList = ArrayList<PathItem>()

		adapter = PathItemAdapter(this, android.R.layout.simple_list_item_1, itemList)
		itemListView.adapter = adapter
		adapter.notifyDataSetChanged()

		itemListView.setOnItemClickListener {_, _, pos, _ ->
			if (currentState.selectMode && selectItem(pos)) {
				runOnUiThread {
					adapter.notifyDataSetChanged()
				}
			}
			else {
				sendRequest(MelodeerRequest("enter", ArrayList<Path>(listOf(itemList[pos].path))))
			}
		}

		itemListView.setLongClickable(true)
		itemListView.setOnItemLongClickListener {_, _, pos, _ ->
			if (selectItem(pos)) {
				currentState.selectMode = true
				runOnUiThread {
					adapter.notifyDataSetChanged()
				}
			}
			true
		}

		retryButton.setOnClickListener {
			sendRequest(MelodeerRequest("enter", ArrayList()))
		}

		playButton.setOnClickListener {
			playSelected()
		}

		stopButton.setOnClickListener {
			stopAll()
		}

		incVolButton.setOnClickListener {
			sendRequest(MelodeerRequest("inc-vol", ArrayList()))
		}

		decVolButton.setOnClickListener {
			sendRequest(MelodeerRequest("dec-vol", ArrayList()))
		}

		nsdManager = getSystemService(Context.NSD_SERVICE) as NsdManager
		startBlockingActivity()
		discover()
	}

	override fun onBackPressed() {

		if (currentState.selectMode) {
			for (item in itemList) {
				item.selected = false
			}
			currentState.selectMode = false
			runOnUiThread {
				adapter.notifyDataSetChanged()
			}
			return

		}

		currentState.currDir?.let { currDir ->
			setStatus(currDir.toString())
			sendRequest(MelodeerRequest("enter", ArrayList(listOf(currDir.parent()))))
		}
	}

	override fun onDestroy() {
		super.onDestroy()
		nsdManager.stopServiceDiscovery(discoveryListener)
	}

	fun discover() {
		nsdManager.discoverServices("_melodeer-service._tcp", NsdManager.PROTOCOL_DNS_SD, discoveryListener)
	}

	fun playSelected() {
		var selected = itemList.filter { it.selected }
		if (selected.isEmpty()) {
			selected = itemList.filter { it.path.type == "f" }
		}
		sendRequest(MelodeerRequest("play", ArrayList(selected.map { it.path })))
	}

	fun stopAll() {
		sendRequest(MelodeerRequest("killall", ArrayList()))
	}

	fun handleResponse(msg: String) {
		runOnUiThread {
			if (currentState.error) {
				currentState.error = false
				retryButton.visibility = View.GONE
				playButton.visibility = View.VISIBLE
				stopButton.visibility = View.VISIBLE
				incVolButton.visibility = View.VISIBLE
				decVolButton.visibility = View.VISIBLE
				itemListView.visibility = View.VISIBLE
			}
		}

		val obj = Json.decodeFromString<MelodeerResponse>(msg)
		if (obj.status == "list") {

			itemList.clear()
			for (file in obj.list) {
				itemList.add(PathItem(file, false))
			}
			currentState.currDir = obj.chdir
			runOnUiThread {
				adapter.notifyDataSetChanged()
			}
			setStatus(Json.encodeToString(obj))
		}
	}

	fun handleError(msg: String) {
		setStatus("Error! ${msg}")
		runOnUiThread {
			if (!currentState.error) {
				currentState.error = true
				retryButton.visibility = View.VISIBLE
				playButton.visibility = View.GONE
				stopButton.visibility = View.GONE
				incVolButton.visibility = View.GONE
				decVolButton.visibility = View.GONE
				itemListView.visibility = View.GONE
			}
		}
	}

	fun startBlockingActivity() {
		runOnUiThread {
			greyOverlay.visibility = View.VISIBLE
			progressBar.visibility = View.VISIBLE
			itemListView.isEnabled = false
			playButton.isEnabled = false
			stopButton.isEnabled = false
			incVolButton.isEnabled = false
			decVolButton.isEnabled = false
		}
	}

	fun endBlockingActivity() {
		runOnUiThread {
			greyOverlay.visibility = View.GONE
			progressBar.visibility = View.GONE
			itemListView.isEnabled = true
			playButton.isEnabled = true
			stopButton.isEnabled = true
			incVolButton.isEnabled = true
			decVolButton.isEnabled = true
		}
	}

	fun sendRequest(rq: MelodeerRequest) {
		if (currentState.serviceInfo == null) {
			setStatus("Could not find host and / or port.")
			return
		}
		startBlockingActivity()
		GlobalScope.launch(Dispatchers.Main) {
			currentState.serviceInfo?.let { serviceInfo ->
				Fuel.post("http://${serviceInfo.host}:${serviceInfo.port}")
				    .jsonBody(Json.encodeToString(rq), charset("UTF-8"))
				    .responseString { _, _, result ->
					result.fold(success={ handleResponse(it) }, failure={ handleError(it.toString()) })
					endBlockingActivity()
				    }
			}
		}
	}

	fun setStatus(msg: String) {
		runOnUiThread {
			stateTextView.text = msg
		}
	}
}
