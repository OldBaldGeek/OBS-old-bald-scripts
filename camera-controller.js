// Camera Motion Controller for PTZ video cameras
// - Aver VC520+ via PTZApp2 http
// - Aver VC520+ or other VISCA camera without velocity control via http VISCA server
// - Vaddio HD-04 camera with good control via http VISCA server
//
// Uses named controls for each instance, appending index (1,2...) to each:
//
// For all camera types:
// - 'Program' indicator for camera in use by OBS. Hidden by default.
// - 'Preview' indicator for camera in use by OBS. Hidden by default.
// - 'Status'  title/status text above Presets
// - 'Presets' list box with camera presets
// - 'Edit'    check box to enable editing of presets
// - 'Hide'    div wrapping preset SHOW and SET buttons
//
// If using camera type aver_ptzapp or visca_jog
// - 'slew_up'      up/down/left/right/zoomin/zoomout slew
// - 'slew_down'
// - 'slew_left'
// - 'slew_right'
// - 'slew_in'
// - 'slew_out'
// - 'jog_up'       up/down/left/right/zoomin/zoomout jog (may be hidden)
// - 'jog_down'
// - 'jog_left'
// - 'jog_right'
// - 'jog_in'
// - 'jog_out'
//
// Only if using camera type visca_joystick
// - 'pan_tilt_stick' canvas for VISCA control of camera with good velocity control
// - 'zoom_stick'
//
// Used by the Save/Load presets modal dialog
// - 'saveLoadModal'    div containing modal dialog
// - 'text-here'        show result text
// - 'savePre'          button to save presets
// - 'loadPre'          button to load presets
// - 'preset_file'      filename control for bulk save/load

// Camera controller objects
var g_cam_controller = {};

// Construct and connect camera controllers
function start_camera() {
    // Get our camera names and serial numbers
    var selectors = cam_data.cam_selectors;
    if (selectors) {
        for (let ix in selectors) {
            g_cam_controller[ix] =
                make_camera_controller(ix, selectors[ix], cam_data.cam_presets);
        }
    }
}

// Make and return a camera controller based on camera info
function make_camera_controller(a_index, a_selector, a_cam_presets) {
    var camera_controller = null;
    if (a_selector.type == 'aver_ptzapp') {
        camera_controller = new AverCameraController(a_index, a_selector, a_cam_presets);
    }
    else if (a_selector.type == 'visca_jog') {
        camera_controller = new ViscaJogCameraController(a_index, a_selector, a_cam_presets);
    }
    else if (a_selector.type == 'visca_joystick') {
        camera_controller = new ViscaJoystickCameraController(a_index, a_selector, a_cam_presets);
    }
    else {
        alert('Camera ' + a_index + '"' + a_selector.name + '" is of unknown type');
    }

    return camera_controller;
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
        cam.show_result('Showing preset: ' + option.text, 2000);
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
        cam.show_result('Setting preset: ' + option.text, 2000);
        cam.set_preset(option.value);
    }
}

var g_save_load = null;

// Button to show savfe/load presets
function do_save_load(a_command)
{
    if (a_command == 'cancel') {
        if (g_save_load && g_save_load.isActive) {
            g_save_load.request_cancel();
        }
        else {
            g_save_load = null;
            document.getElementById("saveLoadModal").style.display = "none";
        }
    }
    else if (a_command == 'save') {
        document.getElementById("savePre").style.visibility = "hidden";
        document.getElementById("loadPre").style.visibility = "hidden";
        g_save_load.get_next_preset(0);
    }
    else if (a_command == 'load') {
        document.getElementById("savePre").style.visibility = "hidden";
        document.getElementById("loadPre").style.visibility = "hidden";
        var fileElem = document.getElementById('preset_file');
        if (fileElem) {
            fileElem.click();
        }
    }
    else {
        // Make a save/load object and show UI
        var p = document.getElementById("text-here");
        g_save_load = new SaveAndLoadPresets(g_cam_controller[a_command], p, 3000);
        g_save_load.finish = finish_save_load;

        p.innerHTML = 'Save or load Camera ' + (a_command+1) + ' presets to a file';

        document.getElementById("saveLoadModal").style.display = "block";
        document.getElementById("loadPre").style.visibility = "visible";
        document.getElementById("savePre").style.visibility = "visible";
    }
}

function finish_save_load(a_text) {
    if (g_save_load) {
        g_save_load.show_result(a_text);
        g_save_load.isActive = false;
    }
}

// Handler for wrapped and hidden file-selection control
function uploadPresetFile(a_files) {
    const selectedFile = a_files[0];
    const reader = new FileReader();
    reader.onload = function(evt) {
        g_save_load.load(evt.target.result);
    };
    reader.readAsText(selectedFile);
}

// Reset camera PTZ
// (Works only for VISCA camera controller)
function do_reset(a_camera) {
    var cam = g_cam_controller[a_camera];
    var request = {};
    request['command'] = 'send_raw';
    request['bytes-to-send'] = '81 01 06 05 FF';
    request['reply-length'] = 0;
    cam.send_visca_request(request)
        .then((response) => {
            console.log('Did reset');
        })
        .catch((a_error) => {
            cam.show_result('Failed Reset: ' + a_error);
        });
}

// Home camera PTZ
function do_home(a_camera) {
    var cam = g_cam_controller[a_camera];
    var request = {};
    request['command'] = 'send_raw';
    request['bytes-to-send'] = '81 01 06 04 FF';
    request['reply-length'] = 0;
    cam.send_visca_request(request)
        .then((response) => {
            console.log('Did Home');
        })
        .catch((a_error) => {
            cam.show_result('Failed Home: ' + a_error);
        });
}

//==============================================================================
// Video camera with PTZ and presets
class CameraController {
    // Make a camera controller based on camera info
    constructor(a_index, a_selector, a_cam_presets) {
        this.index = a_index;
        this.name = a_selector.name;
        this.max_preset = a_selector.max_preset;

        this.msg_timer = null;
        this.edit_mode = false;

        // Populate the preset control with scenes belonging to this camera
        var ele = this.getIndexedElement('Presets');
        for (let ix in a_cam_presets) {
            if (a_cam_presets[ix].camera == this.name) {
                var option = document.createElement("option");
                option.text = a_cam_presets[ix].name;
                option.value = a_cam_presets[ix].preset;
                ele.add(option);
            }
        }

        // Set the initial state of the UI
        this.default_status = 'Presets';
        this.getIndexedElement('Edit').checked = false;
        this.getIndexedElement('Hide').style.visibility = "hidden";
        this.getIndexedElement('Program').style.visibility = "hidden";
        this.getIndexedElement('Preview').style.visibility = "hidden";
    }

    // Show a preset (implementation by subclass)
    show_preset(a_preset_number) {
        console.log('CameraImplementation does not implement show_preset');
    }

    // Set a preset (implementation by subclass)
    set_preset(a_preset_number) {
        console.log('CameraImplementation does not implement set_preset');
    }

    on_message_timeout() {
        // On timeout, set the status back to idle
        this.msg_timer = null;
        this.show_result(this.default_status, 0);
    }

    // Show command status for a period of time (0=permanent)
    show_result(a_text, a_duration_msec = 5000)
    {
        var field = this.getIndexedElement('Status');
        if (field !== null) {
            if (this.msg_timer != null) {
                // Stop existing timer
                window.clearTimeout(this.msg_timer);
                this.msg_timer = null;
            }

            field.innerHTML = a_text;

            if (a_duration_msec > 0) {
                this.msg_timer = window.setTimeout(this.on_message_timeout.bind(this), a_duration_msec);
            }
        }
    }

    // Return a control by ID and camera index, show an error if not found
    getIndexedElement(a_base_id) {
        var retval = document.getElementById(a_base_id + this.index);
        if (retval == null) {
            window.alert('Missing required control "' + a_base_id + this.index + '"');
        }
        return retval;
    }
}

//==============================================================================
// Camera controller for Aver VC520+ via PTZApp2
class AverCameraController extends CameraController {
    constructor(a_index, a_selector, a_cam_presets)
    {
        super(a_index, a_selector, a_cam_presets);

        this.aver_address = cam_data.cam_address;
        this.serial = a_selector.serialnumber;
        console.log('Camera "' + this.name + '" serial "' + this.serial + '"');

        // Map control IDs to PTZApp actions
        this.action_for_id = {};
        this.action_for_id['slew_up'+a_index]    = 'up';
        this.action_for_id['slew_down'+a_index]  = 'down';
        this.action_for_id['slew_left'+a_index]  = 'left';
        this.action_for_id['slew_right'+a_index] = 'right';
        this.action_for_id['slew_in'+a_index]    = 'zoomin';
        this.action_for_id['slew_out'+a_index]   = 'zoomout';

        // Connect the PTZ buttons
        this.connect_button('slew_up');
        this.connect_button('slew_down');
        this.connect_button('slew_left');
        this.connect_button('slew_right');
        this.connect_button('slew_in');
        this.connect_button('slew_out');

        // We can't jog, so hide the jog buttons
        this.getIndexedElement('jog_up').style.visibility = "hidden";
        this.getIndexedElement('jog_down').style.visibility = "hidden";
        this.getIndexedElement('jog_left').style.visibility = "hidden";
        this.getIndexedElement('jog_right').style.visibility = "hidden";
        this.getIndexedElement('jog_in').style.visibility = "hidden";
        this.getIndexedElement('jog_out').style.visibility = "hidden";
    }

    // Select a camera preset by number
    // (Implements base class method)
    show_preset(a_preset_number)
    {
        this.send_ptz_command('gopreset&index=' + a_preset_number);
    }

    // Program a camera preset by number
    // (Implements base class method)
    set_preset(a_preset_number)
    {
        this.send_ptz_command('setpreset&index=' + a_preset_number);
    }

    // Connect a PTZ button
    connect_button(a_button_id) {
        var c = this.getIndexedElement(a_button_id);
        c.addEventListener("pointerdown", (e) => {
            this.pointer_down(e);
        });

        c.addEventListener("pointerup", (e) => {
            this.pointer_up(e);
        });
    }

    pointer_down(e) {
        e.currentTarget.setPointerCapture(e.pointerId);
        this.send_ptz_command(this.action_for_id[e.currentTarget.id] + '1');
    }

    pointer_up(e) {
        this.send_ptz_command(this.action_for_id[e.currentTarget.id] + '0');
        e.currentTarget.releasePointerCapture(e.currentTarget.id);
    }

    // Synchronously GET the request and return the result, or null on error
    send_ptz_command(a_command)
    {
        // Select our camera
        this.send_command('list?action=set&uvcid=' + this.serial)
            .then((response) => {
                // Send the PTZ command
                this.send_command('ptz?action=' + a_command);
            })
            .then((response) => {
                console.log('Completed sending: ' + a_command)
            })
            .catch((a_error) => {
                this.show_result('Failed to select camera: ' + a_error);
            });
    }

    // Send a PTZApp GET request, returning a promise.
    // - Call resolve() on successful transaction
    // - Call reject() on error
    send_command(a_command)
    {
        var url = "http://" + this.aver_address + "/" + a_command;
        return new Promise(
            function(resolve, reject) {
                var req = new XMLHttpRequest();
                console.log('Sending: ' + url)
                req.open('GET', url);

                req.onload = () => {
                    // 200 for web file; 0 for local file
                    // 404 for URL path not found; etc.
                    if (req.readyState === 4) {
                        if ((req.status === 200) || (req.status === 0)) {
                            console.log(req.responseText);
                            resolve();
                        } else {
                            reject('Error from server: ' + req.statusText);
                        }
                    }
                };

                req.onerror = () => {
                    // This sucks: the GET is blocked by CORS, but there seems
                    // to be nothing to tell us that.
                    // So we lie and declare success.
                    // reject('Network error');
                    resolve();
                };

                req.send();
              });
    }
}

//==============================================================================
// Camera controller for VISCA device without slew velocity control
// such as the Aver VC520+
// Has slew and jog buttons for PTZ
class ViscaCameraController extends CameraController {
    constructor(a_index, a_selector, a_cam_presets) {
        super(a_index, a_selector, a_cam_presets);

        // Originally used hostname "localhost" here and in the Visca server.
        // But in Chrome (though not Firefox) we see consistent attempts to
        // open TCP sessions in IPv6, getting RST,ACK (from server or Windows?)
        // Chrome waits about 250 msec and does another IPv6 SYN on a new port
        // After getting another RST,ACK, Chrome waits about 50 msec, then
        // finally starts the session on IPv4.
        // Using 127.0.0.1 eliminates the RST,ACKs and delays.
        this.url = "http://" + cam_data.visca_server_address + "/server";

        // Counter to disambiguate requests for debugging
        this.sendCount = 0;
        this.address = a_selector.address;
        this.slew_velocity = a_selector.slew_velocity;
    }

    // Select a camera preset by number
    // (Implements base class method)
    show_preset(a_preset_number)
    {
        var request = {};
        request['command'] = 'go-preset';
        request['value'] = a_preset_number;
        this.send_visca_request(request)
            .then((response) => {
                console.log('Showed preset ' + request['value']);
            })
            .catch((a_error) => {
                this.show_result('Failed show preset: ' + a_error);
            });
    }

    // Program a camera preset by number
    // (Implements base class method)
    set_preset(a_preset_number)
    {
        var request = {};
        request['command'] = 'set-preset';
        request['value'] = a_preset_number;
        this.send_visca_request(request)
            .then((response) => {
                console.log('Set preset ' + request['value']);
            })
            .catch((a_error) => {
                this.show_result('Failed set preset: ' + a_error);
            });
    }

    // Send a VISCA request, returning a promise.
    // - Call resolve() on successful transaction
    // - Call reject() on error
    send_visca_request(a_request) {
        this.sendCount = this.sendCount + 1;
        var url = this.url;
        a_request['camera'] = this.address;
        var sendCount = this.sendCount;
        a_request['sendCount'] = sendCount;
        console.log( "Send VISCA request", url, a_request );

        return new Promise(
            function(resolve, reject) {
                var req = new XMLHttpRequest();
                req.open('POST', url);
                req.setRequestHeader('Content-Type', 'application/json');

                req.onload = () => {
                    // 200 for web file; 0 for local file
                    // 404 for URL path not found; etc.
                    if (req.readyState === 4) {
                        if ((req.status === 200) || (req.status === 0)) {
                            var response = JSON.parse(req.response);
                            var status = response['status'];
                            if (status == null) {
                                reject('Invalid response from server');
                            }
                            else if (status != 'ok') {
                                reject(response.errors);
                            }
                            else {
                                response['sendCount'] = sendCount;
                                resolve(response);
                            }
                        } else {
                            reject('Error from server: ' + req.statusText);
                        }
                    }
                };

                req.onerror = () => {
                    // Annoyingly, there seems to be nothing to tell us
                    // WHAT failed: no server, ...
                    // statusText is empty
                    // We may just declare persistent failure
                    reject('Network error');
                };

                req.send(JSON.stringify(a_request));
              });
    }

    //==========================================================================
    // Button onclick handlers for various camera actions
    // TODO: these are incomplete until we figure out what to DO with the results...

    do_read_position() {
        var request = {};
        request['command'] = 'report';
        this.send_visca_request(request)
            .then((response) => {
                this.show_result('pan=' + response['pan'] +
                                 '  tilt=' + response['tilt'] +
                                 '  zoom=' + response['zoom']);

                // Stuff the values into the input fields
                document.getElementById("pan_val").value = response['pan'];
                document.getElementById("tilt_val").value = response['tilt'];
                document.getElementById("zoom_val").value = response['zoom'];
            })
            .catch((a_error) => {
                this.show_result('Failed read position: ' + a_error);
            });
    }

    do_read_version_info() {
        var request = {};
        request['command'] = 'version-info';
        this.send_visca_request(request)
            .then((response) => {
                this.show_result('vendor=' + response['vendor'] +
                                 '  model=' + response['model'] +
                                 '  version=' + response['version'] +
                                 '  maxsocket=' + response['max_socket']);
            })
            .catch((a_error) => {
                this.show_result('Failed read version: ' + a_error);
            });
    }

    do_move() {
        var request = {};
        request['command'] = 'moveto';
        request['speed'] = document.getElementById("speed_val").value;
        request['pan']  = document.getElementById("pan_val").value;
        request['tilt'] = document.getElementById("tilt_val").value;
        request['zoom'] = document.getElementById("zoom_val").value;

        this.send_visca_request(request)
            .then((response) => {
                console.log('Moved ');
            })
            .catch((a_error) => {
                this.show_result('Failed move: ' + a_error);
            });
    }

    do_send_raw() {
        var request = {};
        request['command'] = 'send_raw';
        request['bytes-to-send'] = document.getElementById("bytes_to_send").value;
        request['reply-length'] = document.getElementById("reply_length").value;

        this.send_visca_request(request)
            .then((response) => {
                console.log('Sent bytes');
                this.show_result(response['response-bytes']);
            })
            .catch((a_error) => {
                this.show_result('Failed move: ' + a_error);
            });
    }
}

//==========================================================================
// Up/down/left/right slew and jog
// Mostly for Aver AV520+ cameras without slew speed control.
class ViscaJogCameraController extends ViscaCameraController {
    constructor(a_index, a_selector, a_cam_presets) {
        super(a_index, a_selector, a_cam_presets);

        this.actionState = 'IDLE';
        this.jog_repeat = 250; // Jog repeats every jog_repeat msec while mouse held down
        this.jogTimer = null;

        // Map control IDs to (command, value, actionState)
        this.action_for_id = {};
        this.action_for_id['slew_up'+a_index]    = ['tilt', 'up',   'SLEW'];
        this.action_for_id['slew_down'+a_index]  = ['tilt', 'down', 'SLEW'];
        this.action_for_id['slew_left'+a_index]  = ['pan',  'left', 'SLEW'];
        this.action_for_id['slew_right'+a_index] = ['pan',  'right','SLEW'];
        this.action_for_id['jog_up'+a_index]     = ['tilt', '1',    'JOG'];
        this.action_for_id['jog_down'+a_index]   = ['tilt', '-1',   'JOG'];
        this.action_for_id['jog_left'+a_index]   = ['pan',  '1',    'JOG'];
        this.action_for_id['jog_right'+a_index]  = ['pan',  '-1',   'JOG'];

        this.action_for_id['slew_in'+a_index]    = ['zoom', 'in',   'SLEW'];
        this.action_for_id['slew_out'+a_index]   = ['zoom', 'out',  'SLEW'];
        this.action_for_id['jog_in'+a_index]     = ['zoom', '1',    'JOG'];
        this.action_for_id['jog_out'+a_index]    = ['zoom', '-1',   'JOG'];


        this.connect_button('slew_up');
        this.connect_button('slew_down');
        this.connect_button('slew_left');
        this.connect_button('slew_right');
        this.connect_button('jog_up');
        this.connect_button('jog_down');
        this.connect_button('jog_left');
        this.connect_button('jog_right');

        this.connect_button('slew_in');
        this.connect_button('slew_out');
        this.connect_button('jog_in');
        this.connect_button('jog_out');
    }

    connect_button(a_button_id) {
        var c = this.getIndexedElement(a_button_id);

        c.addEventListener("pointerdown", (e) => {
            this.pointer_down(e);
        });

        c.addEventListener("pointerup", (e) => {
            this.pointer_up(e);
        });
    }

    pointer_down(e) {
        var [command, value, state] = this.action_for_id[e.currentTarget.id];
        this.request = {};
        this.request['command'] = command;
        this.request['value'] = value;
        this.request['speed'] = this.slew_velocity;
        this.actionState = state;

        e.currentTarget.setPointerCapture(e.pointerId);
        if (this.actionState == 'JOG') {
            // Jog: send command, start timer to repeat jog
            this.send_visca_request(this.request)
                .then((response) => {
                    if (this.actionState == 'JOG') {
                        // If button still active, start a timer to repeat jog.
                        // Normally the case, but a delay in the server may allow
                        // button-up before we get here.
                        console.log('jog success, start jog timer');
                        this.jogTimer = window.setTimeout(this.on_timer.bind(this), this.jog_repeat);
                    }
                })
                .catch((a_error) => {
                    this.show_result('Failed mousedown: ' + a_error);
                });
        }
        else {
            // slew: send start command
            this.send_visca_request(this.request)
                .then((response) => {
                    console.log('mousedown slew success');
                })
                .catch((a_error) => {
                    this.show_result('Failed mousedown: ' + a_error);
                });
        }
    }

    pointer_up(e) {
        e.currentTarget.releasePointerCapture(e.pointerId);

        if (this.actionState == 'JOG') {
            this.actionState = 'IDLE';
            console.log('mouseup stopping jog timer');
            window.clearTimeout(this.jogTimer);
            this.jogTimer = null;
        }
        else if (this.actionState == 'SLEW') {
            this.request['value'] = 'stop';
            this.send_visca_request(this.request)
                .then((response) => {
                    console.log('mouseup stopped slew');
                })
                .catch((a_error) => {
                    this.show_result('Failed mouseup: ' + a_error);
                })
                .finally(() => {
                    this.actionState = 'IDLE';
                });
        }
    }

    on_timer() {
        if (this.actionState == 'JOG') {
            console.log('timer: repeat jog');
            this.send_visca_request(this.request)
                .then((response) => {
                    console.log('jog timer success. Restarting timer');
                    this.jogTimer = window.setTimeout(this.on_timer.bind(this), this.jog_repeat);
                })
                .catch((a_error) => {
                    this.show_result('Failed mouse timer: ' + a_error);
                });
        }
    }
}

//==============================================================================
// Camera controller for VISCA device with slew velocity control
// such as the Vaddio HD-20
// Has "joysticks" for PTZ
class ViscaJoystickCameraController extends ViscaCameraController {
    constructor(a_index, a_selector, a_cam_presets) {
        super(a_index, a_selector, a_cam_presets);
        this.pantilt = new JoystickPTZ( 'pan_tilt_stick' + this.index, this );
        this.zoom    = new JoystickZoom( 'zoom_stick' + this.index, this );
    }
}

//==========================================================================
// Joystick pan/tilt: velocity set by distance from axis
class JoystickPTZ {
    constructor(a_canvas_id, a_visca_controller) {
        this.canvas_id = a_canvas_id;
        this.visca_controller = a_visca_controller;
        this.pan_max = 0x18;    // Max in Sony definition; max for Vaddio HD-20
        this.tilt_max = 0x14;   // Max for Vaddio HD-20; Sony max is 0x18
        this.dead_limit = 5;    // deadband half-width

        // Requested values set by mouse down, mouse move
        this.active = false;
        this.desired_d_pan = 'stop';
        this.desired_v_pan = 0;
        this.desired_d_tilt = 'stop';
        this.desired_v_tilt = 0;

        // Set by communications
        this.in_progress = false;
        this.last_d_pan = 'stop';
        this.last_v_pan = 0;
        this.last_d_tilt = 'stop';
        this.last_v_tilt = 0;

        this.connect();
    }

    connect() {
        var c = document.getElementById(this.canvas_id);

        c.addEventListener("pointerdown", (e) => {
            // Attend only to main mouse button
            if (e.button === 0) {
                c.setPointerCapture(e.pointerId);
                this.in_progress = false;
                this.last_d_pan = 'stop';
                this.last_v_pan = 0;
                this.last_d_tilt = 'stop';
                this.last_v_tilt = 0;

                this.active = true;
                this.do_joy_action(e);
            }
        });

        c.addEventListener("pointermove", (e) => {
            if (this.active) {
                this.do_joy_action(e);
            }
        });

        c.addEventListener("pointerup", (e) => {
            c.releasePointerCapture(e.pointerId);
            if (this.active) {
                this.active = false;
                console.log('Pointerup: stop');

                var ctx = c.getContext("2d");
                ctx.clearRect(0, 0, c.width, c.height);

                this.desired_d_pan = 'stop';
                this.desired_v_pan = 0;
                this.desired_d_tilt = 'stop';
                this.desired_v_tilt = 0;
                // Perform the action when we can
                this.do_joy_comm();
            }
        });
    }

    // Convert a mouse position to desired pan and tilt directions and velocities
    do_joy_action(e) {
        var c = document.getElementById(this.canvas_id);
        var half_width = c.width/2;
        var half_height = c.height/2;
        let x = Math.min(e.offsetX, c.width) - half_width;
        let y = half_height - Math.min(e.offsetY, c.height);

        // Draw a line from center to mouse
        var ctx = c.getContext("2d");
        ctx.clearRect(0, 0, c.width, c.height);
        ctx.beginPath();
        ctx.moveTo(half_width, half_height);
        ctx.lineTo(e.offsetX, e.offsetY);
        ctx.stroke();

        ctx.beginPath();
        ctx.arc(e.offsetX, e.offsetY, this.dead_limit/2, 0, 2*Math.PI);
        ctx.fill();

        // Convert mouse position to pan and tilt velocities
        this.desired_d_pan = 'stop';
        this.desired_v_pan = 0;
        if (x > this.dead_limit) {
            this.desired_d_pan = 'right';
            this.desired_v_pan = (x - this.dead_limit)/(half_width - this.dead_limit);
        }
        else if (x < -this.dead_limit) {
            this.desired_d_pan = 'left';
            this.desired_v_pan = -(x + this.dead_limit)/(half_width - this.dead_limit);
        }
        // Square the 0 to 1 velocity value to give finer slow-speed resolution
        this.desired_v_pan = (this.desired_v_pan < 1.0)
                ? Math.round(this.desired_v_pan*this.desired_v_pan*this.pan_max)
                : this.pan_max;

        this.desired_d_tilt = 'stop';
        this.desired_v_tilt = 0;
        if (y > this.dead_limit) {
            this.desired_d_tilt = 'up';
            this.desired_v_tilt = (y - this.dead_limit)/(half_height - this.dead_limit);
        }
        else if (y < -this.dead_limit) {
            this.desired_d_tilt = 'down';
            this.desired_v_tilt = -(y + this.dead_limit)/(half_height - this.dead_limit);
        }
        // Square the -1 to +1 value to give finer slow-speed resolution
        this.desired_v_tilt = (this.desired_v_tilt < 1.0)
                ? Math.round(this.desired_v_tilt*this.desired_v_tilt*this.tilt_max)
                : this.tilt_max;

        var text = 'Desired do_joy_action ' + this.desired_d_pan + '(' + this.desired_v_pan + ') ' +
                   this.desired_d_tilt + '(' + this.desired_v_tilt + ')';
        console.log(text);

        // See if we can start the action
        this.do_joy_comm();
    }

    // If communications isn't busy, and a change has been requested, tell the
    // server to move the camera
    do_joy_comm() {
        if ((!this.in_progress) &&
           ((this.desired_v_pan != this.last_v_pan) || (this.desired_v_tilt != this.last_v_tilt) ||
            (this.desired_d_pan != this.last_d_pan) || (this.desired_d_tilt != this.last_d_tilt)))
        {
            // Able to make a change, and change has been requested
            this.in_progress = true;
            this.last_d_pan = this.desired_d_pan;
            this.last_v_pan = this.desired_v_pan;
            this.last_d_tilt = this.desired_d_tilt;
            this.last_v_tilt = this.desired_v_tilt;

            var text = 'do_joy_comm ' + this.desired_d_pan + '(' + this.desired_v_pan + ') ' +
                        this.desired_d_tilt + '(' + this.desired_v_tilt + ')';
            console.log(text);

            var request = {};
            request['command'] = 'slew';
            request['pan-value'] = this.desired_d_pan;
            request['pan-speed'] = this.desired_v_pan;
            request['tilt-value'] = this.desired_d_tilt;
            request['tilt-speed'] = this.desired_v_tilt;
            this.visca_controller.send_visca_request(request)
                .then((response) => {
                    // No longer busy. Check to see if anything has changed.
                    this.in_progress = false;
                    this.do_joy_comm();
                })
                .catch((a_error) => {
                    this.show_result('Failed joystick slew: ' + a_error);
                    // TODO: try to send stop? release capture? Mark idle?
                    console.log('ERROR: joystick slew failed');
                    var c = document.getElementById(this.canvas_id);

                    var ctx = c.getContext("2d");
                    ctx.clearRect(0, 0, c.width, c.height);
                    c.releasePointerCapture(e.pointerId);
                    this.in_progress = false;
                    this.active = false;
                })
        }
    }
}

//==========================================================================
// Joystick zoom: velocity set by distance from axis
class JoystickZoom {
    constructor(a_canvas_id, a_visca_controller) {
        this.canvas_id = a_canvas_id;
        this.visca_controller = a_visca_controller;
        this.zoom_max   = 7;    // Max in Sony definition; max for Vaddio HD-20
        this.dead_limit = 10;   // deadband half-width

        // Requested values set by mouse down, mouse move
        this.active = false;
        this.desired_d_zoom = 'stop';
        this.desired_v_zoom = 0;

        // Set by communications
        this.in_progress = false;
        this.last_d_zoom = 'stop';
        this.last_v_zoom = 0;

        this.connect();
    }

    connect() {
        var c = document.getElementById(this.canvas_id);

        c.addEventListener("pointerdown", (e) => {
            // Attend only to main mouse button
            if (e.button === 0) {
                c.setPointerCapture(e.pointerId);
                this.in_progress = false;
                this.last_d_zoom = 'stop';
                this.last_v_zoom = 0;

                this.active = true;
                this.do_joy_action(e);
            }
        });

        c.addEventListener("pointermove", (e) => {
            if (this.active) {
                this.do_joy_action(e);
            }
        });

        c.addEventListener("pointerup", (e) => {
            c.releasePointerCapture(e.pointerId);
            if (this.active) {
                this.active = false;
                console.log('Pointerup: stop');

                var ctx = c.getContext("2d");
                ctx.clearRect(0, 0, c.width, c.height);

                this.desired_d_zoom = 'stop';
                this.desired_v_zoom = 0;
                // Perform the action when we can
                this.do_joy_comm();
            }
        });
    }

    // Convert a mouse position to desired zoom direction and velocity
    do_joy_action(e) {
        var c = document.getElementById(this.canvas_id);
        var half_width  = c.width/2;
        var half_height = c.height/2;
        let x = Math.min(e.offsetX, c.width) - half_width;
        let y = half_height - Math.min(e.offsetY, c.height);

        // Draw a line from center to mouse
        var ctx = c.getContext("2d");
        ctx.clearRect(0, 0, c.width, c.height);
        ctx.beginPath();
        ctx.moveTo(half_width, half_height);
        ctx.lineTo(half_width, e.offsetY);
        ctx.stroke();

        ctx.beginPath();
        ctx.arc(half_width, e.offsetY, this.dead_limit/4, 0, 2*Math.PI);
        ctx.fill();

        // Convert mouse position to zoom velocity
        this.desired_d_zoom = 'stop';
        this.desired_v_zoom = 0;
        if (y > this.dead_limit) {
            this.desired_d_zoom = 'in';
            this.desired_v_zoom = (y - this.dead_limit)/(half_height - this.dead_limit);
        }
        else if (y < -this.dead_limit) {
            this.desired_d_zoom = 'out';
            this.desired_v_zoom = -(y + this.dead_limit)/(half_height - this.dead_limit);
        }
        this.desired_v_zoom = (this.desired_v_zoom < 1.0)
                ? Math.round(this.desired_v_zoom*this.zoom_max)
                : this.zoom_max;

        var text = 'Desired do_joy_action ' + this.desired_d_zoom + '(' + this.desired_v_zoom + ')';
        console.log(text);

        // See if we can start the action
        this.do_joy_comm();
    }

    // If communications isn't busy, and a change has been requested, tell the
    // server to move the camera
    do_joy_comm() {
        if ((!this.in_progress) &&
           ((this.desired_v_zoom != this.last_v_zoom) || (this.desired_d_zoom != this.last_d_zoom)))
        {
            // Able to make a change, and change has been requested
            this.in_progress = true;
            this.last_d_zoom = this.desired_d_zoom;
            this.last_v_zoom = this.desired_v_zoom;

            var text = 'do_joy_comm ' + this.desired_d_zoom + '(' + this.desired_v_zoom + ')';
            console.log(text);

            var request = {};
            request['command'] = 'zoom';
            request['value'] = this.desired_d_zoom;
            request['speed'] = this.desired_v_zoom;

            this.visca_controller.send_visca_request(request)
                .then((response) => {
                    // No longer busy. Check to see if anything has changed.
                    this.in_progress = false;
                    this.do_joy_comm();
                })
                .catch((a_error) => {
                    this.show_result('Failed joystick slew: ' + a_error);
                    // TODO: try to send stop? release capture? Mark idle?
                    console.log('ERROR: joystick slew failed');
                    var c = document.getElementById(this.canvas_id);
                    var ctx = c.getContext("2d");
                    ctx.clearRect(0, 0, c.width, c.height);
                    c.releasePointerCapture(e.pointerId);
                    this.in_progress = false;
                    this.active = false;
                })
        }
    }
}

//==========================================================================
// Save and Load presets
// TODO: add a cancel function to stop load or save
class SaveAndLoadPresets {
    constructor(a_visca_controller, a_result_text, a_wait_for_movement_msec) {
        this.visca_controller = a_visca_controller;
        this.result_text = a_result_text;
        this.wait_for_preset = a_wait_for_movement_msec;
        this.presetTimer = null;
        this.presets = [];
        this.cancel = false;
        this.isActive = false;
    }

    show_result(a_text) {
        this.result_text.innerHTML = a_text;
    }

    request_cancel() {
        this.cancel = true;
    }

    get_next_preset(a_preset_number) {
        if (this.cancel) {
            this.finish("Canceled saving presets");
            return;
        }

        this.isActive = true;
        this.show_result('Saving preset ' + a_preset_number);

        var request = {};
        request['command'] = 'go-preset';
        request['value'] = a_preset_number;
        this.visca_controller.send_visca_request(request)
            .then((response) => {
                console.log('Got preset ' + request['value']);
                // Wait for the camera to move before reading its position
                this.presetTimer = window.setTimeout(this.on_save_preset_timer.bind(this),
                                                     this.wait_for_preset,
                                                     a_preset_number);
            })
            .catch((a_error) => {
                if (this.a_preset_number == 0) {
                    // Some cameras allow preset 0, some don't. Try 1
                    this.get_next_preset(1);
                }
                else {
                    // For any other error, save results thus far and stop.
                    // (Ideally, we would parse the error and look for
                    // an explicit "reset number out of range", but our visca
                    // server currently doesn't return it nicely, and it isn't
                    // clear that camera from different vendors report the
                    // error in the same way.)
                    // Actually, Aver VC520+ NEVER returns an error: it just
                    // interprets anything higher than 10 as preset 10.
                    window.clearTimeout(this.presetTimer);
                    this.presetTimer = null;
                    this.save_preset_file();
                }
            });
    }

    save_preset_file() {
        console.log(this.presets);
        var json_string = JSON.stringify(this.presets, null, 4);
        var file = new Blob([json_string], {type: 'text/plain'});

        var a = document.createElement("a");
        a.href = URL.createObjectURL(file);
        a.download = this.visca_controller.name + '_camera_presets.json';
        a.click();
        this.finish("Finished saving presets");
    }

    on_save_preset_timer(a_preset_number) {
        // Read the camera's position and zoom
        this.presetTimer = null;

        var request = {};
        request['command'] = 'report';
        this.visca_controller.send_visca_request(request)
            .then((response) => {
                // Save the info for this preset
                var pre = {"preset":a_preset_number,
                           "pan":response['pan'],
                           "tilt":response['tilt'],
                           "zoom":response['zoom']};
                this.presets.push(pre);

                if (a_preset_number < this.visca_controller.max_preset) {
                    this.get_next_preset(a_preset_number+1);
                }
                else {
                    this.save_preset_file();
                }
            })
            .catch((a_error) => {
                this.finish('Failed read position: ' + a_error);
            });
    }

    // Convert JSON preset data and start setting presets
    load(a_json_string) {
        this.isActive = true;
        this.presets = JSON.parse(a_json_string);
        this.move_to_next_preset(0);
    }

    // Move to the position specified by presets[a_preset_index]
    move_to_next_preset(a_preset_index) {
        if (this.cancel) {
            this.finish("Canceled loading presets");
            return;
        }

        var request = {};
        request['command'] = 'moveto';
        request['pan']  = this.presets[a_preset_index].pan;
        request['tilt'] = this.presets[a_preset_index].tilt;
        request['zoom'] = this.presets[a_preset_index].zoom;
        this.show_result('Loading preset ' + this.presets[a_preset_index].preset);
        this.visca_controller.send_visca_request(request)
            .then((response) => {
                console.log('Moved to preset[' + a_preset_index + ']');
                // Wait for the camera to move before saving as preset
                this.presetTimer = window.setTimeout(this.on_load_preset_timer.bind(this),
                                                     this.wait_for_preset,
                                                     a_preset_index);
            })
            .catch((a_error) => {
                this.finish('Failed move: ' + a_error);
                window.clearTimeout(this.presetTimer);
                this.presetTimer = null;
            });
    }

    on_load_preset_timer(a_preset_index) {
        if (this.cancel) {
            this.finish("Canceled loading presets");
            return;
        }

        // Set a camera preset
        this.presetTimer = null;

        var request = {};
        request['command'] = 'set-preset';
        request['value'] = this.presets[a_preset_index].preset;
        this.visca_controller.send_visca_request(request)
            .then((response) => {
                console.log('Loaded preset ' + request['value']);
                a_preset_index = a_preset_index + 1;
                if (a_preset_index < this.presets.length) {
                    this.show_result('Loaded preset ' + request['value']);
                    this.move_to_next_preset(a_preset_index);
                }
                else {
                    this.finish("Finished loading presets");
                }
            })
            .catch((a_error) => {
                this.finish('Failed set preset: ' + a_error);
            });
    }
}

