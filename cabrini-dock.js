// All in one control dock for streaming at Cabrini by John Hartman
// - Aver camera control
// - slide show clickable buttons (alternative to hotkeys used by script)

// Default address of the AVER camera server, in case we can't read the configuration file
var g_aver_address = 'localhost:36680';

// Address of the OBS Websocket server
var g_websocket_address = "127.0.0.1:4444";

// Names of the OBS camera sources
var g_cam_name0 = "Camera 1";
var g_cam_name1 = "Camera 2";

// Name of the slideshow source
var g_slideshow_source_name = "SimpleSlides: music";


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
        
        //var field = document.getElementById('Title' + this.index);
        //field.innerHTML = this.name;

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
var sceneRefreshInterval = 0;
var socketisOpen = false;

var currentState =
{
    "previewScene": "",     // the name of the current preview scene
    "programScene": "",     // the name of the current live scene
}

function connectWebsocket()
{
    websocket = new WebSocket("ws://" + g_websocket_address);
    websocket.onopen = function (evt)
    {
        socketisOpen = true;
        clearInterval(intervalID);
        intervalID = 0;

        // Get initial program and preview values
        sendPayload( {
            "message-id": "get-current-scene",
            "request-type": "GetCurrentScene" } );

        sendPayload( {
            "message-id": "get-preview-scene",
            "request-type": "GetPreviewScene" } );

        pollSlideshow();
    };

    websocket.onclose = function (evt)
    {
        socketisOpen = false;
        if (intervalID == 0) {
            intervalID = setInterval(connectWebsocket, 5000);
        }
    };

    websocket.onmessage = function (evt)
    {
        var data = JSON.parse(evt.data);
        if (data.hasOwnProperty("message-id")) {
            handleResponse(data)
        } else if (data.hasOwnProperty("update-type")) {
            handleStateChangeEvent(data)
        } else {
            console.log('websocket onmessage unable to handle message.', data);
        }
    };

    websocket.onerror = function (evt)
    {
        socketisOpen = false;
        if (intervalID == 0) {
            intervalID = setInterval(connectWebsocket, 5000);
        }
    };
}

function sendPayload(a_payload)
{
    if (socketisOpen) {
        websocket.send(JSON.stringify(a_payload));
    } else {
        console.error('unable to send command. socket not open.', a_payload);
    }
}

function sendHotkey(a_key)
{
    sendPayload( {
        "message-id": "did-hotkey",
        "request-type": "TriggerHotkeyByName",
        "hotkeyName": a_key } );
}

// Return the name of the camera in the scene's source array, or "no camera" if none.
function getCameraName(a_sources)
{
    let retval = 'no camera';
    for (const source of a_sources) {
        if (source.type == 'dshow_input') {
            retval = source.name;
            break;
        }
    }
    
    return retval;
}

function processProgramScene(a_data)
{
    if (a_data.hasOwnProperty('scene-name')) {
        currentState.programScene = a_data['scene-name'];
    }
    else {
        currentState.programScene = a_data['name'];
    }

    var camera = getCameraName(a_data['sources']);
    console.log('Program scene changed to ' + currentState.programScene + ' using ' + camera);
    
    var c0 = document.getElementById('Program0');
    var c1 = document.getElementById('Program1');
    if (camera == g_cam_name0) {
        c0.style.visibility = 'visible';
        c1.style.visibility = 'hidden';
    }
    else if (camera == g_cam_name1) {
        c0.style.visibility = 'hidden';
        c1.style.visibility = 'visible';
    }
    else {
        c0.style.visibility = 'hidden';
        c1.style.visibility = 'hidden';
    }
}

function processPreviewScene(a_data)
{
    if (a_data.hasOwnProperty('scene-name')) {
        currentState.previewScene = a_data['scene-name'];
    }
    else {
        currentState.previewScene = a_data['name'];
    }

    var camera = getCameraName(a_data['sources']);
    console.log('Preview scene changed to ' + currentState.previewScene + ' using ' + camera);

    var c0 = document.getElementById('Preview0');
    var c1 = document.getElementById('Preview1');
    if (camera == g_cam_name0) {
        c0.style.visibility = 'visible';
        c1.style.visibility = 'hidden';
    }
    else if (camera == g_cam_name1) {
        c0.style.visibility = 'hidden';
        c1.style.visibility = 'visible';
    }
    else {
        c0.style.visibility = 'hidden';
        c1.style.visibility = 'hidden';
    }
}

// Process responses to requests we sent
function handleResponse(data)
{
    const messageId = data["message-id"];
    switch (messageId) {
        case "get-current-scene":
            processProgramScene(data);
            break;

        case "get-preview-scene":
            processPreviewScene(data);
            break;
            
        case "did-hotkey":
            // console.log('Did a hotkey.');
            break;
            
        case "get-slideshow-settings":
            processSlideshowSettings(data);
            break;

        default:
            console.error('handleResponse got unknown event.', data);
            break;
    }
}

// Process incoming websocket messages
function handleStateChangeEvent(a_data)
{
    const updateType = a_data['update-type'];
    switch (updateType) {
        case 'PreviewSceneChanged':
            processPreviewScene(a_data);
            break;

        case 'SwitchScenes':
            processProgramScene(a_data);
            break;

        default:
            break;
    }
}

//==============================================================================
// Button to do a slideshow action
function do_slides(a_action)
{
    console.log('Slideshow ' + a_action);
    switch (a_action) {
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

// Show information about the current slide
// We could do this after WE change slides, but there is no notification
// of when a keyboard shortcut changes slides.
//function showSlideInfo()
//{
//    sendPayload( {
//        "message-id": "show-slide-info",
//        "request-type": "GetSourceSettings",
//        "sourceName": "SimpleSlides: music",
//        "sourceType": "image_source" } );
//}
//
// Add this case to handleResponse
//        case "show-slide-info":
//            let path = ''
//            if (data.hasOwnProperty('sourceSettings')) {
//                path = data['sourceSettings'].file;
//            }
//
//            document.getElementById('slidePath').innerHTML = path;
//            break;
//
var slideShowTimer = 0;
var slideCount = 0;
var lastSlide = "";
function processSlideshowSettings(a_data)
{
    if (a_data.sourceSettings.file != lastSlide) {
        console.log("Slide " + slideCount + " " + a_data.sourceSettings.file);
        lastSlide = a_data.sourceSettings.file;

        var img = new Image(); // 1280, 720);   // Create new img element
        img.addEventListener('load', function() {
            console.log("Draw image here for " + lastSlide);
            console.log("Width=" + img.width + " NatWidth=" + img.naturalWidth);

            // var div = document.getElementById('SlideImage');
            // 320:180
            // 400:225
            // 480:270
            // 560:315
            // Wider canvas stretches the BUTTONS as well
            // Limit width, and at least see the left end of the slide
            var canvas = document.getElementById('SlideCanvas');
            canvas.width = 400;
            canvas.height = 315;
            console.log("Canvas Width=" + canvas.width + " height=" + canvas.height);

            var ctx = canvas.getContext('2d');
            ctx.drawImage(img, 0, 0, 1280, 720, -20, -20, 560, 315);
        }, false);
        img.src = "file://" + lastSlide;
    }
    slideCount += 1;

    if (slideShowTimer == 0) {
        slideShowTimer = setInterval(pollSlideshow, 5000);
    }
}

function pollSlideshow()
{
    sendPayload( {
        "message-id": "get-slideshow-settings",
        "request-type": "GetSourceSettings",
        "sourceName": g_slideshow_source_name } );
}
