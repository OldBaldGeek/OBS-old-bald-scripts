// All in one control dock for streaming at Cabrini by John Hartman
// - Aver camera control
// - slide show clickable buttons (alternative to hotkeys used by script)
// - preview of current and next slide
// - some basic statistics

// OBS Websockets documentation
//    https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md
// Formal definitions as a json file
//    https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.json

// Default address of the AVER camera server, in case we can't read the configuration file
var g_aver_address = 'localhost:36680';

// Address of the OBS Websocket 5.0 server
var g_websocket_address = "127.0.0.1:4455";

// Names of the OBS camera sources in our scene collection
var g_cam_name0 = "Camera 1";
var g_cam_name1 = "Camera 2";

// The name of a GDI Text source that SimpleSlides.lua uses to tell us
// the names of the current and next slides.
var g_slide_info_source = "SimpleSlides_info"

// Slide poll rate in msec
var g_slidePollRate = 500

// Stats poll rate in msec
// Not a multiple of g_slidePollRate, to minimize them happening at the the same time
// on the theory that this might strain frame time
var g_statsPollRate = 4003

//==============================================================================
// String shown above the preset lists when no action is in progress
var default_status = 'Presets';

class CameraController
{
    constructor(a_index, a_name, a_serial) {
        this.index = a_index;
        this.name = a_name;
        this.serial = a_serial;
        this.edit_mode = false;
        this.msg_timer = null;

        console.log('Camera "' + this.name + '" serial "' + this.serial + '"');
        
        // Populate the preset control with scenes belonging to this camera
        var presets = cam_data.cam_presets;
        if (presets) {
            var ele = document.getElementById('Presets' + this.index);
            for (let ix in presets) {
                if (presets[ix].camera == this.name) {
                    var option = document.createElement("option");
                    option.text = presets[ix].name;
                    option.value = presets[ix].preset;
                    ele.add(option);
                }
            }
        }

        // Set the initial state of the UI
        document.getElementById('Edit' + this.index).checked = false;
        document.getElementById('Hide' + this.index).style.visibility = "hidden";
        document.getElementById('Program' + this.index).style.visibility = "hidden";
        document.getElementById('Preview' + this.index).style.visibility = "hidden";
    }

    // Select a camera preset by number
    show_preset(a_preset_number)
    {
        this.send_ptz_command('gopreset&index=' + a_preset_number);
    }

    // Program a camera preset by number
    set_preset(a_preset_number)
    {
        this.send_ptz_command('setpreset&index=' + a_preset_number);
    }

    // Synchronously GET the request and return the result, or null on error
    send_ptz_command(a_command)
    {
        // Select our camera
        this.send_command('list?action=set&uvcid=' + this.serial);

        // Send the PTZ command
        this.send_command('ptz?action=' + a_command);
    }

    // GET the request and return the result, or null on error
    send_command(a_command)
    {
        try
        {
            var req = new XMLHttpRequest();
            var url = "http://" + g_aver_address + "/" + a_command;
            console.log('Sending: ' + url)
            req.open("GET", url, true);
            req.onload = function (e) {
                // 200 for web file, 0 for local file
                if (req.readyState === 4) {
                    if ((req.status === 200) || (req.status === 0)) {
                        console.log(req.responseText);
                    } else {
                        console.log('error: ' + req.statusText);
                    }
                }
            };
            req.onerror = function (e) {
                console.log('on-error: ' + req.statusText);
            };

            req.send();
        }
        catch(e)
        {
            console.log('Request threw an exception')
        }
    }

    // Show command status for a period of time (0=permanent)
    showResult(a_text, a_duration_msec)
    {
        var field = document.getElementById('Status' + this.index);
        if (field !== null) {
            if (this.msg_timer != null) {
                // Stop existing timer
                clearTimeout(this.msg_timer);
                this.msg_timer = null;
            }

            field.innerHTML = a_text;

            if (a_duration_msec > 0) {
                this.msg_timer = setTimeout( function (a_cam) {
                    // On timeout, set the status back to idle
                    a_cam.msg_timer = null;
                    a_cam.showResult(default_status, 0);
                }, a_duration_msec, this);
            }
        }
    }
}

//==============================================================================
// Camera data
var g_cam_controller = {};

// Called when everything is ready
function loaded()
{
    // "cam_data" is in camera-data.js, shared with Camera-buddy, CamToggle etc.
    g_aver_address = cam_data.cam_address;

    // Get our camera names and serial numbers
    var selectors = cam_data.cam_selectors;
    if (selectors) {
        for (let ix in selectors) {
            g_cam_controller[ix] =
                new CameraController(ix, selectors[ix].name, selectors[ix].serialnumber);
        }
    }

    // Start the Websocket interface
    window.addEventListener("load", connectWebsocket, false);
    connectWebsocket();
}

// Start or stop an action, usually based on mouse button down/up
function do_action(a_camera, a_action, a_start_stop)
{
    let command;
    if (a_start_stop == "start") {
        command = a_action + '1';
    }
    else {
        command = a_action + '0';
    }
    
    g_cam_controller[a_camera].send_ptz_command(command);
}

// Checkbox to toggle camera preset edit mode
function do_edit(a_camera, a_checkbox)
{
    g_cam_controller[a_camera].edit_mode = a_checkbox.checked;

    var ele = document.getElementById('Hide' + a_camera);
    ele.style.visibility = (a_checkbox.checked) ? 'visible' : 'hidden';
    
    if (!a_checkbox.checked) {
        // Remove any selection from the present list
        ele = document.getElementById('Presets' + a_camera);
        ele.selectedIndex = -1; 
        ele.blur();
    }
}

// Click on a preset in the <select> list
function do_select(a_camera, a_select)
{
    // In normal mode, move the camera, don't keep selection.
    // In edit mode, just set a selection for SHOW and SET buttons.
    var cam = g_cam_controller[a_camera];
    if (!cam.edit_mode) {
        let option = a_select.options[a_select.selectedIndex]
        cam.show_preset(option.value);

        // Remove the selection, since the camera may not stay on that preset
        a_select.selectedIndex = -1; 
        a_select.blur();
    }
}

// Button to show the preset specified by the current <select>
function do_show_preset(a_camera)
{
    var ele = document.getElementById('Presets' + a_camera);
    if ((ele != null) && (ele.selectedIndex >= 0)) {
        var option = ele.options[ele.selectedIndex];

        var cam = g_cam_controller[a_camera];
        cam.showResult('Showing preset: ' + option.text, 2000);
        cam.show_preset(option.value);
    }
}

// Button to set the preset specified by the current <select>
function do_set_preset(a_camera)
{
    var ele = document.getElementById('Presets' + a_camera);
    if ((ele != null) && (ele.selectedIndex >= 0)) {
        var option = ele.options[ele.selectedIndex];

        var cam = g_cam_controller[a_camera];
        cam.showResult('Setting preset: ' + option.text, 2000);
        cam.set_preset(option.value);
    }
}

//==============================================================================
// Websockets interface

var intervalID = 0;
var socketisOpen = false;

function connectWebsocket()
{
    websocket = new WebSocket("ws://" + g_websocket_address);
    websocket.onopen = function (evt)
    {
        console.log("websocket.onopen");
        clearInterval(intervalID);
        intervalID = 0;
        clearInterval(slideShowTimer);
        slideShowTimer = 0;
        resetStats();

        socketisOpen = true;
        console.log("websocket.onopen marked open");
    };

    websocket.onclose = function (evt)
    {
        console.log('websocket.onclose');
        document.getElementById('stats').innerHTML = "Not connected to OBS";

        socketisOpen = false;

        clearInterval(slideShowTimer);
        slideShowTimer = 0;

        if (intervalID == 0) {
            intervalID = setInterval(connectWebsocket, 5000);
        }
    };

    websocket.onerror = function (evt)
    {
        // Close the socket, try again in 5 seconds: OBS may not be running.
        console.log("websocket.onerror");
        document.getElementById('stats').innerHTML = "Not connected to OBS";

        socketisOpen = false;
        if (intervalID == 0) {
            intervalID = setInterval(connectWebsocket, 5000);
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
                    pollSlideshow();

                    // Start getting stats
                    pollStats();
                    break;

                case 5:
                    // Event
                    handleEvent(data.d);
                    break;

                case 7:
                    // Response to request
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
        break;

    // These usually come in pairs: STARTING, STARTED; STOPPING, STOPPED
    case 'StreamStateChanged':
        console.log('Stream State changed:', a_data.eventData.outputActive, a_data.eventData.outputState);
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
    // was ctx.drawImage(img1, 0, 0, 1280, 720, -20, -20, 560, 315);
    // was ctx.drawImage(img1, 0, 0, 1280, 720, -20, -25, 560, 315);
    ctx.drawImage(a_image, 50, 60, 1200, 550, 0, 0, 500, 250);
}

// Show name and image for current and next slides.
var slideShowTimer = 0;
var lastSlide = "";
function processSlideshowSettings(a_data)
{
    var slideFile = a_data.inputSettings.text;
    var nextFile  = a_data.inputSettings.next;

    if (slideFile != lastSlide) {
        console.log("Slide " + slideFile);
        console.log('nextFile is', nextFile);

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

    if (slideShowTimer == 0) {
        slideShowTimer = setInterval(pollSlideshow, g_slidePollRate);
    }
}

// Get statistics
var statsTimer = 0;
function pollStats()
{
    sendPayload( 6, { "requestType": "GetStats",
                      "requestId": "get-stats" } );
}

var lastAverageRenderTime = 0;
var lastAverageRenderTimeTime = "";
var lastRenderSkip = 0;
var lastRenderSkipTime = "";
var lastOutputSkip = 0;
var lastOutputSkipTime = "";

// This is a full reset, when we have just connected and have no history.
// TODO: we may also want a "relative" reset that would remember skip and count
// values at the time of reset, and subtract them from the displayed values.
function resetStats()
{
    lastAverageRenderTime = 0;
    lastAverageRenderTimeTime = "";
    lastRenderSkip = 0;
    lastRenderSkipTime = "";
    lastOutputSkip = 0;
    lastOutputSkipTime = "";
}

function processStats(a_data)
{
    var str = 'CPU usage: ' + parseFloat(a_data.cpuUsage).toFixed(1) + '%<br>';

    var renderTime = parseFloat(a_data.averageFrameRenderTime);
    if (renderTime > lastAverageRenderTime) {
        lastAverageRenderTime = renderTime;

        var d = new Date;
        lastAverageRenderTimeTime = '. Maximum ' + renderTime.toFixed(1) +
                                    ' msec at ' + d.toLocaleTimeString();

    }
    str += 'Average frame render time: ' + renderTime.toFixed(1) + ' msec' +
            lastAverageRenderTimeTime + '<br>';

    var delta = a_data.renderSkippedFrames - lastRenderSkip;
    if (delta != 0) {
        lastRenderSkip = a_data.renderSkippedFrames;
        var d = new Date;
        if (delta == 1) {
            lastRenderSkipTime = '. Last skip at ' + d.toLocaleTimeString();
        } else {
            lastRenderSkipTime = '. Last skip: ' + delta + ' frames at ' + 
                                 d.toLocaleTimeString();
        }
    }
    str += 'Skipped/Rendered: ' + 
            a_data.renderSkippedFrames + ' / ' + a_data.renderTotalFrames + 
            lastRenderSkipTime + '<br>';
    
    delta = a_data.outputSkippedFrames - lastOutputSkip;
    if (delta != 0) {
        lastOutputSkip = a_data.outputSkippedFrames;
        var d = new Date;
        if (delta == 1) {
            lastOutputSkipTime = '. Last skip at ' + d.toLocaleTimeString();
        } else {
            lastOutputSkipTime = '. Last skip: ' + delta + ' frames at ' + 
                                 d.toLocaleTimeString();
        }
    }
    str += 'Skipped/Output: ' + 
            a_data.outputSkippedFrames + ' / ' + a_data.outputTotalFrames +
            lastOutputSkipTime + '<br>';

    document.getElementById('stats').innerHTML = str;

    if (statsTimer == 0) {
        statsTimer = setInterval(pollStats, g_statsPollRate);
    }
}
