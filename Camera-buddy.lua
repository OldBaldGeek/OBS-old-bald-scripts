obs = obslua
local socket = require("ljsocket")

local version = "0.6"

-- Set true to get debug printing
local debug_print_enabled = false

-- Description displayed in the Scripts dialog window
function script_description()
    debug_print("in script_description")
    return '<h2>Camera-buddy Version ' .. version ..'</h2>' ..
        [[
           <p>Send camera PTZ preset commands when a scene is Previewed/shown,
           unless the camera is already in use on the Program; in which
           case wait to send the PTZ when the scene is Programmed/activated.</p>
           
           <p>Camera commands are specified by adding Text(GDI+) sources to
           scenes with names of the format "PTZ: Altar". These sources are
           created by the script for each preset in the camera-data.js file.
           Please do not attempt to create them manually.</p>
        ]]
end

-- We are controlled by sources whose names begin with source_key
local source_key = 'PTZ:'

-- Configuration file, in same directory as this script
local config_file = 'camera-data.js'

-- Configuration items Read from config_file
local ip_address_and_port = '127.0.0.1:36680'
local camera_presets = {}
local camera_selectors = {}

local ip_address = nil
local ip_port = nil

-- Flag to hold off camera motion until we are fully loaded
local load_complete = false

-- Indexed by camera number, holds the last preset sent to the camera
local last_cam_setting = {}

-- A list of PTZ sources which we created, and must release at exit
local ptzs_we_made = {}

local hotkey_transition_id = obs.OBS_INVALID_HOTKEY_ID

-- Duration (editable) of PTZ pulses
local pulse_duration = 100

-- Initial settings for our magic sources
local PTZ_JSON_DATA = [[
{
"bk_opacity":77,
"font":{"face":"Arial",
  "flags":0,
  "size":60,
  "style":"Regular"},
"text":" The camera is in use by the Program scene. \n It will be re-positioned when this scene \n transitions to Program. "
}
]]

local ptz_text = ' The camera is in use by the Program scene. \n It will be set to "%s" when this scene \n transitions to Program. '

-- Log a message if debugging is enabled
function debug_print(a_string)
    if debug_print_enabled then
        print(a_string)
    end
end

function script_load(settings)
    print("Camera-buddy version " .. version)
    
    -- Read our configuration data
    load_camera_data()

    -- Connect our hotkeys
    hotkey_transition_id = obs.obs_hotkey_register_frontend("camera_buddy_transition_button", "[Camera-buddy]Transition", do_transition)
    local save_array = obs.obs_data_get_array(settings, "transition_hotkey")
    obs.obs_hotkey_load(hotkey_transition_id, save_array)
    obs.obs_data_array_release(save_array)

    obs.obs_frontend_add_event_callback(handle_frontend_event)
    local sh = obs.obs_get_signal_handler()
    obs.signal_handler_connect(sh, "source_activate", on_source_activate)
end

function script_unload()
    debug_print("in script_unload")
	release_ptz_sources()
    camera_presets = nil
    camera_selectors = nil
    last_cam_setting = nil
    debug_print("  end script_unload")
end

function script_defaults(settings)
    debug_print("in script_defaults")
end

function script_properties()
    debug_print("in script_properties")
    
    local props = obs.obs_properties_create()
    obs.obs_properties_add_int(props, "pulse_duration",  "Pulse duration msec", 1, 1000, 10)
    obs.obs_properties_add_button(props, "up_button",    " UP ", up_button_clicked)
    obs.obs_properties_add_button(props, "down_button",  "DOWN", down_button_clicked)
    obs.obs_properties_add_button(props, "left_button",  "LEFT", left_button_clicked)
    obs.obs_properties_add_button(props, "right_button", "RIGHT", right_button_clicked)

    obs.obs_properties_add_button(props, "zoom_in_button",  "IN ", zoom_in_button_clicked)
    obs.obs_properties_add_button(props, "zoom_out_button", "OUT", zoom_out_button_clicked)

    return props
end

function script_update(settings)
    debug_print('in script_update')

    pulse_duration = obs.obs_data_get_int(settings, "pulse_duration")
end

function script_save(settings)
    debug_print("in script_save")

    local save_array = obs.obs_hotkey_save(hotkey_transition_id)
    obs.obs_data_set_array(settings, "transition_hotkey", save_array)
    obs.obs_data_array_release(save_array)
end

function on_source_activate(cs)
    if load_complete then
        local source = obs.calldata_source(cs, "source")
        if source ~= nil then
            local name = obs.obs_source_get_name(source)
            ix,len = string.find(name, source_key)
            if ix == 1 then
                -- Hide the status message: the front-end event is too late
                -- and allows the message to show briefly
                -- debug_print( 'on_source_activate disabling "' .. name .. '"' )
                obs.obs_source_set_enabled(source, false)
             end
        end
    end
end

local change_count = 0
function handle_frontend_event(event)
    if event == obs.OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED then
        if load_complete then
            do_scene_change("OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED")
        else
            -- OBS_FRONTEND_EVENT_FINISHED_LOADING works on initial run,
            -- but doesn't happen if we reload this script.
            -- So we ignore the first OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED,
            -- but act on subsequent ones
            debug_print("Early OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED")
            change_count = change_count + 1
            if change_count > 1 then
                load_complete = true
                configure_ptz_sources()
                do_scene_change("OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED")
            end
        end
	elseif event == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING then
        -- Postpone actions until everything is stable
        if not load_complete then
            load_complete = true
            configure_ptz_sources()
            do_scene_change("OBS_FRONTEND_EVENT_FINISHED_LOADING")
        end
    end
end

-- Load configuration from a file shared with our browser dock
function load_camera_data()
    -- Content is json, wrapped in a JavaScript variable so that
    -- the browser dock can load it as code for security simplicity
    path = script_path() .. config_file
    infile = io.open(path, 'r')
    if infile then
        print("Reading camera settings from " .. path)
        local raw = infile:read("*a")
        infile:close()

        local ix, jx = string.find(raw, "cam_data=")
        if ix == 1 then
            local data = string.sub(raw, jx+1, #raw-1)
            local obj = obs.obs_data_create_from_json(data)
            if obj then
                ip_address_and_port = obs.obs_data_get_string(obj, "cam_address")
                print('  camera address=' .. ip_address_and_port)

                -- Mapping of camera names to serial numbers and protocol info
                camera_selectors = {}
                local arr = obs.obs_data_get_array(obj, "cam_selectors")
                if arr then
                    for ix=1, obs.obs_data_array_count(arr) do
                        local element = obs.obs_data_array_item(arr, ix-1)
                        local name = obs.obs_data_get_string(element, "name")
                        -- We make an item for this even though there is
                        -- currently only one piece of data, because future.
                        local item = {}
                        item.serialnumber = obs.obs_data_get_string(element, "serialnumber")
                        print('  camera selector "' .. name .. '" is serialnumber ' .. item.serialnumber)
                        camera_selectors[name] = item
                        obs.obs_data_release(element)
                    end
                    obs.obs_data_array_release(arr)
                end
                
                -- Mapping of preset names to camera names and presets
                camera_presets = {}
                arr = obs.obs_data_get_array(obj, "cam_presets")
                if arr then
                    for ix=1, obs.obs_data_array_count(arr) do
                        local element = obs.obs_data_array_item(arr, ix-1)
                        local name = obs.obs_data_get_string(element, "name")
                        local item = {}
                        item.camera = obs.obs_data_get_string(element, "camera")
                        item.preset = obs.obs_data_get_string(element, "preset")

                        print('  preset "' .. name .. '" is camera ' .. item.camera .. ', preset ' .. item.preset)
                        camera_presets[name] = item
                        obs.obs_data_release(element)
                    end
                    obs.obs_data_array_release(arr)
                end
                obs.obs_data_release(obj)
            else
                print('ERROR: cannot parse json from "' .. path .. '"')
            end
        else
            print('ERROR: cannot parse data in "' .. path .. '"')
        end
    else
        print('ERROR: cannot read "' .. path .. '"')
    end
end

-- Parse the preset specifier from a Source name and return it.
-- Return nil if the name isn't a "magic" anmes
function get_preset_from_source_name(a_name)
    local retval = nil
    local ix, iy = string.find(a_name, source_key)
    if ix == 1 then
        retval = string.sub(a_name, iy+2)
    end

    return retval
end

-- Find special text sources that control us and be sure they are configured
function configure_ptz_sources()
    debug_print("in configure_ptz_sources")

    -- Release any sources we made during a previous load
    release_ptz_sources()

    -- Make or configure a Source for each or our presets
    for key, data in pairs(camera_presets) do
        local settings = obs.obs_data_create_from_json(PTZ_JSON_DATA)
        local text = string.format(ptz_text, key)
        obs.obs_data_set_string(settings, 'text', text)

        local name = source_key .. ' ' .. key
        local source = obs.obs_get_source_by_name(name)
        if source ~= nil then
            debug_print('  Updating existing PTZ source "' .. name .. '"')
            obs.obs_source_update(source, settings)
            obs.obs_source_release(source) 
        else
            debug_print('  Making PTZ source "' .. name .. '"')
            local new_source = obs.obs_source_create("text_gdiplus", name, settings, nil)
            if new_source ~= nil then
                table.insert(ptzs_we_made, new_source)
                -- This source will be released by release_ptz_sources() on shutdown
            else
                print('ERROR: failed to created PTZ source "' .. name .. '"')
            end
        end

        obs.obs_data_release(settings)
    end

    -- See if there are any magic sources that don't specify a known preset
    local sources = obs.obs_enum_sources()
    for _, source in ipairs(sources) do
        local source_name = obs.obs_source_get_name(source)
        local preset = get_preset_from_source_name(source_name)
        if preset ~= nil then
            local preset_data = camera_presets[preset]
            if preset_data == nil then
                print('ERROR: PTZ source "' .. source_name .. '" specifies an unknown preset')
            end
        end
    end
    obs.source_list_release(sources)
end

-- Release any PTZ sources that we made when the scene collection was loaded
function release_ptz_sources()
    for i, source in ipairs(ptzs_we_made) do
        local source_name = obs.obs_source_get_name(source)
        debug_print('Releasing source ' .. i .. ' "' .. source_name .. '"')
        obs.obs_source_release(source)
    end
    ptzs_we_made = {}
end

-- If the scene has a source_key source, return the associated
-- source_name, camera, and preset numbers, else nil, nil, nil
-- If we don't have camera data for source_name, return camera=1 preset=0
function get_preset_info(label, scenesource)
    local source_name = nil
    local cam = nil
    local num = nil

    local scene_name = obs.obs_source_get_name(scenesource)
    debug_print(label .. ' get_preset_info for "' .. scene_name .. '"')

    local scene = obs.obs_scene_from_source(scenesource)
    local items = obs.obs_scene_enum_items(scene)
    for i, item in pairs(items) do
        local item_source = obs.obs_sceneitem_get_source(item)
        local item_name   = obs.obs_source_get_name(item_source)
        local preset      = get_preset_from_source_name(item_name)
        if preset ~= nil then
            local preset_data = camera_presets[preset]
            if preset_data then
                debug_print('   preset key is "' .. item_name .. '"')
                source_name = item_name
                cam = preset_data.camera
                num = preset_data.preset
                break
            else
                print('ERROR: unknown preset "' .. item_name .. '"')
            end
        end
    end
    obs.sceneitem_list_release(items)

    return source_name, cam, num
end

-- Handle OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED,
-- which is also generated with OBS_FRONTEND_EVENT_SCENE_CHANGED
function do_scene_change(label)
    debug_print('do_scene_change ' .. label)

    -- Check Program scene first, since it controls what Preview can do
    local program_source_name = nil
    local program_cam = nil
    local program_num = nil
    local scenesource = obs.obs_frontend_get_current_scene()
    if scenesource ~= nil then
        local program_scene_name = obs.obs_source_get_name(scenesource)
        program_source_name, program_cam, program_num = get_preset_info("Program", scenesource)
        if program_source_name ~= nil then
            debug_print('Program: "' .. program_scene_name .. '" uses "' .. program_source_name ..
                  '" Cam(' .. program_cam .. ', ' .. program_num .. ')')
            set_camera_to(program_cam, program_num)
        end

        obs.obs_source_release(scenesource)
    end

    scenesource = obs.obs_frontend_get_current_preview_scene()
    if scenesource ~= nil then
        local preview_scene_name = obs.obs_source_get_name(scenesource)
        local preview_source_name, preview_cam, preview_num = get_preset_info("Preview", scenesource)
        if preview_source_name == nil then
            debug_print('Preview: "' .. preview_scene_name .. '" not using PTZ.')
        else
            -- Get the source associated with the key source in this scene
            -- so that we can enable or disable it
            local preview_scene = obs.obs_scene_from_source(scenesource)
            if preview_scene == nil then 
                print( "ERROR: no preview scene") 
                return
            end

            local scene_item = obs.obs_scene_find_source(preview_scene, preview_source_name)
            if scene_item == nil then 
                print( "ERROR: no scene_item for source") 
                return
            end

            local preview_source = obs.obs_sceneitem_get_source(scene_item)
            if preview_source == nil then 
                print( "ERROR: no preview source for item") 
                return
            end

            if (program_cam == nil) or (program_cam ~= preview_cam) then
                -- Program scene isn't using a camera, or is using a different camera than Preview.
                -- Move the Preview camera to preview settings. Show no banner.
                debug_print('Preview: "' .. preview_scene_name .. '" uses "' .. preview_source_name ..
                      '" Cam(' .. preview_cam .. ', ' .. preview_num .. ')')
                set_camera_to(preview_cam, preview_num)
                obs.obs_source_set_enabled(preview_source, false)
            elseif program_num == preview_num then
                -- Preview uses the same camera and preset as Program.
                -- No adjustment needed, show no message
                debug_print('  Peview: "' .. preview_scene_name .. '" uses same Cam(' .. preview_cam .. ', ' .. preview_num .. ') as Program')
                obs.obs_source_set_enabled(preview_source, false)
            else
                -- Preview uses the same camera as Program, but a different setting.
                -- Camera will need to be adjusted when the Preview goes live.
                -- Until then, show a message
                debug_print('Preview: "' .. preview_scene_name .. '" has to wait to use "' .. preview_source_name ..
                      '" Cam(' .. preview_cam .. ', ' .. preview_num .. ')')
                obs.obs_source_set_enabled(preview_source, true)
            end
        end

        obs.obs_source_release(scenesource)
    end
end

-- Move a Camera
-- We send only on change. That means than manual adjustment of the camera
-- will be persistent until a scene is selected that uses a different preset.
function set_camera_to(camera, preset)
    local last_preset = last_cam_setting[camera]
    if (last_preset == nil) or (last_preset ~= preset) then
        -- Either first time setting this camera, or preset has changed
        if send_command(camera, "gopreset&index=" .. preset) then
            debug_print('Set camera ' .. camera .. ' to preset ' .. preset)
            last_cam_setting[camera] = preset
        else
            debug_print('Failed to set camera ' .. camera .. ' to preset ' .. preset)
            -- kill "last setting" to force send on next request
            last_cam_setting[camera] = nil
        end
    end
end

-- Send a command over HTTP to the camera
-- This is synchronous, so may cause frames to be dropped if the camera's
-- response is delayed (or non-existant), but seems to work for a USB camera.
-- Return true for success, false if send fails
function send_command(camera, command)
    local retval = false
    if ip_address == nil then
        local ix = string.find(ip_address_and_port, ':')
        ip_address = string.sub(ip_address_and_port, 1, ix-1)
        ip_port = string.sub(ip_address_and_port, ix+1)
    end

    -- Get protocol info for the camera
    local selector = camera_selectors[camera]
    if selector == nil then
        print('ERROR: no camera selector for "' .. camera .. '"')
    else
        retval = http_request(ip_address, ip_port, '/list?action=set&uvcid=' .. selector.serialnumber)
    end

    if retval then
        retval = http_request(ip_address, ip_port, '/ptz?action=' .. command)
    end
    return retval
end

-- Send an HTTP GET request to the specified address and port
-- Return true for success, false if connection fails
function http_request(a_address, a_port, a_url)
    debug_print('Sending http_request "GET ' .. a_url .. '" to ' .. a_address .. ':' .. a_port)

    local socket = assert(socket.create("inet", "stream", "tcp"))
    if not socket:connect(a_address, a_port) then
        -- We don't assert connect failure: during startup, script may run
        -- before camera software is awake, so we just return false.
        -- We do assert subsequent send/receive
        print("Camera socket:connect failed")
        return false
    else
        -- We use HTTP 1.0 so the server will close the session
        assert(socket:send(
            "GET " .. a_url .. " HTTP/1.0\r\n"..
            "Host: " .. a_address .. ':' .. a_port .. "\r\n" ..
            "\r\n"), "socket:send failed")

        local chunk = assert(socket:receive(), "socket:receive failed")
        if chunk then
            local ix,iy = string.find(chunk, '\r\n')
            if ix then
                debug_print('Got ' .. string.len(chunk) .. ' bytes: "' .. string.sub(chunk, 1, ix-1) .. '"')
            end

            ix,iy = string.find(chunk, 'Content%-Type%: application%/json')
            if ix then
                -- Get the json data, or at least a chunk of it, to avoid
                -- rude session closures.
                chunk = assert(socket:receive(), "socket:receive failed")
                -- debug_print('json data "' .. chunk .. '"')
            end
        end
        assert(socket:close())
    end
    return true
end

-- Callback to end a pulsed command
local delayed_camera = nil
local delayed_command = nil
function timer_callback()
    debug_print('in delayed_command')
    if delayed_command then
        send_command(delayed_camera, delayed_command)
        delayed_camera = nil
        delayed_command = nil
    end
    obs.remove_current_callback()
end

-- Send a command, then end it after a specified interval
function send_pulse_command(command)
    -- TODO: add support for multiple camera
    local camera = 1

    -- For greater duration accuracy, we might try one or both of
    -- * Keep the socket open during the pulse
    -- * Start the timer BEFORE the first send_command
    debug_print('send_pulse_command "' .. command .. '"')
    send_command(camera, command .. '1')
    delayed_camera = camera
    delayed_command = command .. '0'
    obs.timer_add(timer_callback, pulse_duration)
end

function up_button_clicked(props, p)
    debug_print("in up_button_clicked")
    send_pulse_command( "up" )
end

function down_button_clicked(props, p)
    debug_print("in down_button_clicked")
    send_pulse_command( "down" )
end

function left_button_clicked(props, p)
    debug_print("in left_button_clicked")
    send_pulse_command( "left" )
end

function right_button_clicked(props, p)
    debug_print("in right_button_clicked")
    send_pulse_command( "right" )
end

function zoom_in_button_clicked(props, p)
    debug_print("in zoom_in_button_clicked")
    send_pulse_command( "zoomin" )
end

function zoom_out_button_clicked(props, p)
    debug_print("in zoom_out_button_clicked")
    send_pulse_command( "zoomout" )
end

function preset_button_clicked(props, p)
    -- TODO: add support for multiple cameras
    debug_print("in preset_button_clicked")
    send_command( 1, "gopreset&index=0" )
end

function do_transition(pressed)
    if pressed then
        obs.obs_frontend_preview_program_trigger_transition()
    end
end
