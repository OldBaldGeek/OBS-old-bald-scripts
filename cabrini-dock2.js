// All in one control dock for streaming at Cabrini by John Hartman
// - Aver camera control
// - slide show clickable buttons (alternative to hotkeys used by script)
// - preview of current and next slide
// - some basic statistics
var g_version = "2.0";

// OBS Websockets documentation
//    https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md
// Formal definitions as a json file
//    https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.json

// Address of the OBS Websocket 5.0 server
var g_websocket_address = "127.0.0.1:4455";

// Reconnection attempt interval
var g_connectInterval = 5000

// Names of the OBS camera sources in our scene collection
var g_cam_name0 = "Camera 1";
var g_cam_name1 = "Camera 2";

// The name of the image source that SimpleSlides.lua uses to show slides,
// and to tell us the names of the current and next slides.
var g_slide_info_source = "SimpleSlides: music"

// Slide poll rate in msec
var g_slidePollRate = 500

// Stats poll rate in msec
// Not a multiple of g_slidePollRate, to minimize them happening at the the same time
// on the theory that this might strain frame time
var g_statsPollRate = 4003

// Accumulate log text, to be written to source object for analysis.
var logData = "";

//==============================================================================

// Called when everything is ready
function loaded()
{
    // Construct and connect camera controllers
    start_camera();

    // Start the Websocket interface
//    window.addEventListener("load", connectWebsocket, false);

    // Wait a bit to let OBS get ready before connecting
//    intervalID = setTimeout(connectWebsocket, g_connectInterval);
}

//==============================================================================
// Websockets interface

var intervalID = 0;
var socketisOpen = false;

function connectWebsocket()
{
    console.log("New websocket at " + Date.now());
    websocket = new WebSocket("ws://" + g_websocket_address);
    websocket.onopen = function (evt)
    {
        console.log("websocket.onopen at " + Date.now());
        clearTimeout(intervalID);
        intervalID = 0;

        resetStats();

        socketisOpen = true;
    };

    websocket.onclose = function (evt)
    {
        console.log("websocket.onclose at " + Date.now());
        document.getElementById('stats').innerHTML = "Not connected to OBS";

        socketisOpen = false;

        clearInterval(slideShowTimer);
        slideShowTimer = 0;

        clearInterval(statsTimer);
        statsTimer = 0;

        clearTimeout(intervalID);
        intervalID = setTimeout(connectWebsocket, g_connectInterval);
    };

    websocket.onerror = function (evt)
    {
        // Close the socket, try again in 5 seconds: OBS may not be running.
        if (socketisOpen) {
            console.log("websocket.onerror after full open " + Date.now());
            websocket.close();
        } else {
            console.log("websocket.onerror during connection attempt at " + Date.now());
        }
    };

    // Received message
    websocket.onmessage = function (evt)
    {
        var data = JSON.parse(evt.data);
        if (data.hasOwnProperty("op")) {
            switch (data.op) {
                case 0:
                    // Hello from server
                    console.log('websocket Hello:', data.d.obsWebSocketVersion);
                    
                    // Respond, subscribing to Scene and Output events
                    sendPayload( 1, {
                                   "rpcVersion": data.d.rpcVersion,
                                // "authentication": string,
                                   "eventSubscriptions": (1<<2) + (1<<6)
                                 } );
                    break;

                case 2:
                    // Identified
                    console.log('websocket Identified:', data.d.negotiatedRpcVersion);

                    // Get initial program and preview scenes
                    sendPayload( 6, { "requestType": "GetCurrentProgramScene",
                                      "requestId": "get-program-scene"} );
                    sendPayload( 6, { "requestType": "GetCurrentPreviewScene",
                                      "requestId": "get-preview-scene"} );

                    // Start getting slideshow data
                    if (slideShowTimer == 0) {
                        slideShowTimer = setInterval(pollSlideshow, g_slidePollRate);
                    }

                    // Start getting stats
                    if (statsTimer == 0) {
                        statsTimer = setInterval(pollStats, g_statsPollRate);
                    }
                    break;

                case 5:
                    // Event from OBS
                    handleEvent(data.d);
                    break;

                case 7:
                    // Response to a previous request
                    if (data.d.requestStatus.result) {
                        handleResponse(data.d)
                    } else {
                        console.log("websocket.onmessage error:", data.d.requestId, data.d.requestStatus.code, data.d.requestStatus.comment );
                    }
                    break;

                default:
                    console.log('websocket onmessage: unknown opcopde.', data.op);
                    break;
            }
        } else {
            console.log('websocket onmessage: no opcopde.', data);
        }
    };
}

// Handle an OBS event
function handleEvent(a_data)
{
    switch (a_data.eventType) {
    case 'CurrentProgramSceneChanged':
        processProgramScene(a_data.eventData.sceneName);
        break;

    case 'CurrentPreviewSceneChanged':
        processPreviewScene(a_data.eventData.sceneName);
        break;

    // These usually come in pairs: STARTING, STARTED; STOPPING, STOPPED
    case 'RecordStateChanged':
        console.log('Record State changed:', a_data.eventData.outputActive, a_data.eventData.outputState);
        if (a_data.eventData.outputState == "OBS_WEBSOCKET_OUTPUT_STARTING") {
            logData += "Recording starting " + Date().toLocaleString() + "<br>";
        } else if (a_data.eventData.outputState == "OBS_WEBSOCKET_OUTPUT_STOPPED") {
            logData += "Recording stopped " + Date().toLocaleString() + "<br>";
            saveLog();
        }
        break;

    // These usually come in pairs: STARTING, STARTED; STOPPING, STOPPED
    case 'StreamStateChanged':
        console.log('Stream State changed:', a_data.eventData.outputActive, a_data.eventData.outputState);
        if (a_data.eventData.outputState == "OBS_WEBSOCKET_OUTPUT_STARTING") {
            logData += "Streaming starting " + Date().toLocaleString() + "<br>";
        } else if (a_data.eventData.outputState == "OBS_WEBSOCKET_OUTPUT_STOPPED") {
            logData += "Streaming stopped " + Date().toLocaleString() + "<br>";
            saveLog();
        }
        break;

    default:
        console.log('unhandled websocket event', a_data.eventType);
        break;
    }
}

// Process responses to requests we sent
function handleResponse(a_data)
{
    switch (a_data.requestId) {
        case "get-program-scene":
            processProgramScene(a_data.responseData.currentProgramSceneName);
            break;

        case "get-preview-scene":
            processPreviewScene(a_data.responseData.currentPreviewSceneName);
            break;
            
        case "did-hotkey":
            // console.log('Did a hotkey.');
            break;
            
        case "get-slideshow-settings":
            processSlideshowSettings(a_data.responseData);
            break;

        case "Program":
            processSceneSettings(a_data.responseData, a_data.requestId);
            break;

        case "Preview":
            processSceneSettings(a_data.responseData, a_data.requestId);
            break;

        case "get-stats":
            processStats(a_data.responseData);
            break;

        case "save-log-data":
            console.log('Saved log data.');
            break;

        default:
            console.error('handleResponse got unknown response:', a_data.requestType, a_data.requestId);
            break;
    }
}

function sendPayload(a_opcode, a_payload)
{
    if (socketisOpen) {
        try {
            pay = JSON.stringify( {"op": a_opcode, "d": a_payload } )
            websocket.send(pay);
        } catch (error) {
            console.error("sendPayload threw", error);
            websocket.close();
        }
    } else {
        console.error('Unable to send command. Socket not open.', a_payload);
    }
}

function sendHotkey(a_key)
{
    console.log('send hotkey:', a_key);
    sendPayload( 6, { "requestType": "TriggerHotkeyByName",
                      "requestId": "did-hotkey",
                      "requestData": {
                         "hotkeyName": a_key }
                    } );
}

// Map scene names to the camera(s) used by the scenes.
var camera_for_scene = new Map();

// Set camera indicators for this scene, or request scene data
function doIndicators(a_scene, a_prog_prev)
{
    if (camera_for_scene.has(a_scene)) {
        // We saw this scene before
        setCameraIndicators( camera_for_scene.get(a_scene), a_prog_prev );
    } else {
        // Read the scene's properties. Reply will call setCameraIndicators
        scene_awaiting_items = a_scene;
        sendPayload( 6, { "requestType": "GetSceneItemList",
                          "requestId": a_prog_prev,
                          "requestData": {
                             "sceneName": a_scene }
                        } );
    }
}

function setCameraIndicators(a_cameras, a_prog_prev)
{
    var vis0 = 'hidden';
    var vis1 = 'hidden';
    if (a_cameras.indexOf(g_cam_name0) >= 0) {
        vis0 = 'visible';
    }
    if (a_cameras.indexOf(g_cam_name1) >= 0) {
        vis1 = 'visible';
    }

    document.getElementById(a_prog_prev + '0').style.visibility = vis0;
    document.getElementById(a_prog_prev + '1').style.visibility = vis1;
}

function processProgramScene(a_name)
{
    doIndicators(a_name, "Program");
}

function processPreviewScene(a_name)
{
    doIndicators(a_name, "Preview");
}

// Process the response to a request for scene settings
function processSceneSettings(a_data, a_prog_prev)
{
    // Get a list of any and all cameras in the scene
    // NOTE: not recursive, so won't find cameras in scenes being used
    // as sources by this scene.
    var cams = '';
    for (const sceneItem of a_data.sceneItems) {
        if (sceneItem.inputKind == 'dshow_input') {
            cams += sceneItem.sourceName + ',';
        }
    }
    camera_for_scene.set(a_data.name, cams);
    setCameraIndicators(cams, a_prog_prev);
}

//==============================================================================
// Button to do a slideshow action
// Names sent to sendHotKey must match those defined in SimpleSlides.lua
function do_slides(a_action)
{
    console.log('Slideshow ' + a_action);
    switch (a_action) {
    case 'Hide':
        sendHotkey("camtoggle_clean_button");
        break;
        
    case 'Toggle':
        sendHotkey("camtoggle_button");
        break;
        
    case 'Next':
        sendHotkey("simpleslides_next_button");
        break;
        
    case 'Previous':
        sendHotkey("simpleslides_previous_button");
        break;
        
    case 'Reload':
        sendHotkey("simpleslides_reset_button");
        break;

    default:
        console.error('do_slides got unknown action.', a_action);
        break;
    }
}

// Get properties of the slideshow
function pollSlideshow()
{
    sendPayload( 6, { "requestType": "GetInputSettings",
                      "requestId": "get-slideshow-settings",
                      "requestData": {
                         "inputName": g_slide_info_source }
                    } );
}

// Draw an image
function myDrawImage(a_element, a_image)
{
    // Limit width, and at least see the left end of the slide
    var canvas = document.getElementById(a_element);
    canvas.width  = 500;
    canvas.height = 250;

    var ctx = canvas.getContext('2d');
    ctx.drawImage(a_image, 50, 60, 1200, 550, 0, 0, 500, 250);
}

// Show name and image for current and next slides.
var slideShowTimer = 0;
var lastSlide = "";
function processSlideshowSettings(a_data)
{
    var slideFile = a_data.inputSettings.file;
    var nextFile  = a_data.inputSettings.next_file;

    if (slideFile != lastSlide) {
        lastSlide = slideFile;

        var img1 = new Image();
        img1.addEventListener('load',
                              function() {
                                  myDrawImage('Slide1Canvas', img1);
                              },
                              false);
        img1.src = "file://" + slideFile;
        document.getElementById('slide1Title').innerHTML = 'Current: ' + slideFile;

        var img2 = new Image();
        if (nextFile) {
            img2.addEventListener('load',
                                  function() {
                                      myDrawImage('Slide2Canvas', img2);
                                  },
                                  false);
            img2.src = "file://" + nextFile;
        } else {
            nextFile = '(none)';
            myDrawImage('Slide2Canvas', img2);
        }
        document.getElementById('slide2Title').innerHTML = 'Next: ' + nextFile;
    }
}

// Track skipped/los frames
class FrameStats
{
    constructor(a_name)
    {
        this.name = a_name;
        this.lastSkip = 0;
        this.lastTotal = 0;
        this.lastSkip_base = 0;
        this.lastTotal_base = 0;
        this.lastSkipTime = "";
    }

    // Total reset, as after a new websocket connection
    reinitialize()
    {
        this.lastSkip = 0;
        this.lastTotal = 0;
        this.lastSkip_base = 0;
        this.lastTotal_base = 0;
        this.lastSkipTime = "";
    }

    // UI reset, so viewed values start over from 0
    reset()
    {
        this.lastSkip_base  = this.lastSkip;
        this.lastTotal_base = this.lastTotal;
        this.lastSkipTime = "";
    }

    // Update with new data, return a string with results
    update(a_skipped, a_total)
    {
        var delta = a_skipped - this.lastSkip;
        if (delta != 0) {
            var d = new Date;
            if (delta == 1) {
                this.lastSkipTime = '.&nbsp;&nbsp;&nbsp;Last skip at ' + d.toLocaleTimeString();
            } else {
                this.lastSkipTime = '.&nbsp;&nbsp;&nbsp;Last skip: ' + delta + ' frames at ' +
                                     d.toLocaleTimeString();
            }
        }

        this.lastSkip = a_skipped;
        this.lastTotal = a_total;
        var str = this.name +
               (a_skipped - this.lastSkip_base) +
               ' of ' +
               (a_total - this.lastTotal_base) +
               this.lastSkipTime + '<br>';

        if (delta != 0) {
            // Save for persistent log
            logData += str;
        }

        return str;
    }
}

// Get statistics
var statsTimer = 0;
function pollStats()
{
    sendPayload( 6, { "requestType": "GetStats",
                      "requestId": "get-stats" } );
}

var maxCPU_usage= 0;
var maxCPU_usageTime = "";

var maxAverageRenderTime = 0;
var maxAverageRenderTimeTime = "";

var renderStats = new FrameStats('Render skipped ');
var outputStats = new FrameStats('Output skipped ');

// This is a full reset, when we have just connected and have no history.
function resetStats()
{
    maxCPU_usage = 0;
    maxCPU_usageTime = "";

    maxAverageRenderTime = 0;
    maxAverageRenderTimeTime = "";

    renderStats.reinitialize();
    outputStats.reinitialize();
}

// Pseudo-reset from UI
function reset_stats()
{
    maxCPU_usage = 0;
    maxCPU_usageTime = "";
    maxAverageRenderTime = 0;
    maxAverageRenderTimeTime = "";
    renderStats.reset();
    outputStats.reset();

    // Update the displayed data
    pollStats();
}

function processStats(a_data)
{
    var cpuUsage = parseFloat(a_data.cpuUsage);
    var logIt = (cpuUsage > maxCPU_usage);
    if (logIt) {
        maxCPU_usage = cpuUsage
        var d = new Date;

        maxCPU_usageTime = '.&nbsp;&nbsp;&nbsp;Maximum ' + cpuUsage.toFixed(1) +
                           '&percnt; at ' + d.toLocaleTimeString();
    }
    var str = 'CPU usage ' + cpuUsage.toFixed(1) + '&percnt;' +
              maxCPU_usageTime + '<br>';
    var statText = str;
    if (logIt) {
        // Save for persistent log
        logData += str;
    }

    var renderTime = parseFloat(a_data.averageFrameRenderTime);
    logIt = (renderTime > maxAverageRenderTime);
    if (logIt) {
        maxAverageRenderTime = renderTime;

        var d = new Date;
        maxAverageRenderTimeTime = '.&nbsp;&nbsp;&nbsp;Maximum ' + renderTime.toFixed(1) +
                                   ' msec at ' + d.toLocaleTimeString();
    }
    str = 'Average frame render ' + renderTime.toFixed(1) + ' msec' +
           maxAverageRenderTimeTime + '<br>';
    statText += str;
    if (logIt) {
        // Save for persistent log
        logData += str;
    }

    statText += renderStats.update(a_data.renderSkippedFrames, a_data.renderTotalFrames);
    statText += outputStats.update(a_data.outputSkippedFrames, a_data.outputTotalFrames);

    document.getElementById('stats').innerHTML = statText;
}

// Save our log to our interface object.
// When OBS saves the scene collection to json, we can harvest the data
function saveLog()
{
    console.log('Saving log data' + logData);
    sendPayload( 6, { "requestType": "SetInputSettings",
                      "requestId": "save-log-data",
                      "requestData": {
                         "inputName": g_slide_info_source,
                         "inputSettings" : {
                             "saved_log" : logData 
                         } }
                    } );
}

// Form UI: dump stat log
function dump_stats()
{
    document.getElementById('log_data').innerHTML = logData;
}
