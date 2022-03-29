// Simple Aver camera control by John Hartman

// Default, in case we can't read json file written by our script
var a_address = 'localhost:36680';

// Camera to be used by this instance
var g_camera = ''
var g_camera_serial = ''

// String shown above the preset list when no action is in progress
var default_status = 'Presets';

// Called when everything is ready
function loaded()
{
    // "cam_data" is in camera-data.js, shared with Camera-buddy, CamToggle etc.
    a_address = cam_data.cam_address;

    var camera_serialnumbers = {};
    var selectors = cam_data.cam_selectors;
    if (selectors) {
        for (let ix in selectors) {
            var name = selectors[ix].name;
            var serialnumber = selectors[ix].serialnumber;
            console.log('Camera "' + name + '" serial "' + serialnumber + '"');
            camera_serialnumbers[name] = serialnumber
        }
    }

    // If there is a query string "camera=XXX" use XXX as our camera
    console.log('Called from ' + window.location.href);
    let str = window.location.href
    let ix = str.search(/\?camera\=/);
    if (ix > 0) {
        g_camera = str.substring(ix+8);
        console.log('Using camera from query string "' + g_camera + '"');
        g_camera_serial = camera_serialnumbers[g_camera];
        if (g_camera_serial == null) {
            // Unknown camera. Use the first camera
            g_camera_serial = selectors[0].serialnumber;
        }
    }
    else {
        // No query string. Use the first camera
        g_camera = selectors[0].name
        g_camera_serial = selectors[0].serialnumber
    }

    console.log('Using camera "' + g_camera + '" serial "' + g_camera_serial + '"');
    showResult('Using camera ' + g_camera, 2000);

    // Populate the preset control with scenes belonging to our camera
    var presets = cam_data.cam_presets;
    if (presets) {
        var field = document.getElementById( 'Presets' );
        if (field !== null) {
            for (let ix in presets) {
                if (presets[ix].camera == g_camera) {
                    var option = document.createElement("option");
                    option.text = presets[ix].name;
                    option.value = presets[ix].preset;
                    field.add(option);
                }
            }
        }
    }
}

// Start or stop an action, usually based on mouse button down/up
function do_action(a_action, a_start_stop)
{
    var command;
    if (a_start_stop == "start") {
        command = a_action + '1';
    }
    else {
        command = a_action + '0';
    }
    
    send_ptz_command(command);
}

// Select a camera preset by number
function do_preset(a_preset_number)
{
    send_ptz_command('gopreset&index=' + a_preset_number);
}

// Program a camera preset by number
function set_preset(a_preset_number)
{
    send_ptz_command('setpreset&index=' + a_preset_number);
}

// Synchronously GET the request and return the result, or null on error
function send_ptz_command(a_command)
{
    // Select our camera
    send_command('list?action=set&uvcid=' + g_camera_serial)

    // Send the PTZ command
    send_command('ptz?action=' + a_command);
}

// GET the request and return the result, or null on error
function send_command(a_command)
{
    try
    {
        var req = new XMLHttpRequest();
        var url = "http://" + a_address + "/" + a_command;
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

var msg_timer = null;

// Show command status for a period of time (0=permanent)
function showResult( a_text, a_duration_msec )
{
    var field = document.getElementById( 'Status' );
    if (field !== null) {
        if (msg_timer != null) {
            // Stop existing timer
            clearTimeout(msg_timer);
            msg_timer = null;
        }

        field.innerHTML = a_text;

        if (a_duration_msec > 0) {
            msg_timer = setTimeout( function () {
                // On timeout, set the status back to idle
                msg_timer = null;
                showResult(default_status,0);
            }, a_duration_msec);
        }
    }
}

// Select a preset
function do_select(a_select)
{
    let option = a_select.options[a_select.selectedIndex]
    do_preset(option.value);
    showResult('Selected preset: ' + option.text, 2000);

    // Remove the selection, since the camera may not stay on that preset
    a_select.selectedIndex = -1; 
    a_select.blur();
}

// Button to show a preset
function do_show_preset()
{
    var ele = document.getElementById( 'Presets' );
    if (ele != null) {
        let option = ele.options[ele.selectedIndex]
        do_preset(option.value);

        showResult('Showing preset: ' + option.text, 2000);
    }
}

// Button to set a preset
function do_set_preset()
{
    var ele = document.getElementById( 'Presets' );
    if (ele != null) {
        let option = ele.options[ele.selectedIndex]
        set_preset(option.value);

        showResult('Showing preset: ' + option.text, 2000);
    }
}

// Go to the specified page, passing camera name
function change_page(a_page)
{
    console.log('Going to ' + a_page);
    window.location.replace(a_page + '?camera=' + g_camera);
}
