obs = obslua

local program_name = "MarkerMaker"
local version = "2.0"

-- Set true to get debug printing
local debug_print_enabled = false

-- Edited/persisted items
local timestamp_offset = 0
local log_scenes = false
local text1 = ''
local text2 = ''
local text3 = ''
local text4 = ''
local color0 = 0
local color1 = 0
local color2 = 0
local color3 = 0
local color4 = 0

-- Implementation items
local logfile = nil
local markerNumber = 1
local time_zero = 0

local hotkey_key1_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_key2_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_key3_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_key4_id = obs.OBS_INVALID_HOTKEY_ID

-- Description displayed in the Scripts dialog window
function script_description()
    debug_print("in script_description")
    return '<h2>' .. program_name .. ' Version ' .. version ..'</h2>' ..
        [[
           <p>When recording is active, use hot keys and scene changes to
           generate timestamped markers to facilitate editing in Reaper or
           Shotcut. Output is a .CSV file.</p>

           <p><b>To import the marker file in Reaper</b>, set Reaper timeline
           format to "Seconds," then select "View," "Region/Marker Manager,"
           "Options," "Import..."</p>

           <p><b>To use the markers in Shotcut</b>, close the Shotcut project.
           Use MarkMunger.py to merge the marker file into the .MLT file, then
           continue editing in Shotcut.</p>
        ]]
end

-- Log a message if debugging is enabled
function debug_print(a_string)
    if debug_print_enabled then
        print(a_string)
    end
end

function script_load(settings)
    print(program_name .. " version " .. version)

    -- Connect our hotkeys
    hotkey_key1_id = obs.obs_hotkey_register_frontend(program_name .. "_key1", 
                     "[" .. program_name .. "]KEY1", log_key1)
    hotkey_key2_id = obs.obs_hotkey_register_frontend(program_name .. "_key2", 
                     "[" .. program_name .. "]KEY2", log_key2)
    hotkey_key3_id = obs.obs_hotkey_register_frontend(program_name .. "_key3", 
                     "[" .. program_name .. "]KEY3", log_key3)
    hotkey_key4_id = obs.obs_hotkey_register_frontend(program_name .. "_key4", 
                     "[" .. program_name .. "]KEY4", log_key4)

    local save_array = obs.obs_data_get_array(settings, "key1_hotkey")
    obs.obs_hotkey_load(hotkey_key1_id, save_array)
    obs.obs_data_array_release(save_array)

    save_array = obs.obs_data_get_array(settings, "key2_hotkey")
    obs.obs_hotkey_load(hotkey_key2_id, save_array)
    obs.obs_data_array_release(save_array)

    save_array = obs.obs_data_get_array(settings, "key3_hotkey")
    obs.obs_hotkey_load(hotkey_key3_id, save_array)
    obs.obs_data_array_release(save_array)

    save_array = obs.obs_data_get_array(settings, "key4_hotkey")
    obs.obs_hotkey_load(hotkey_key4_id, save_array)
    obs.obs_data_array_release(save_array)

    obs.obs_frontend_add_event_callback(handle_frontend_event)

    if obs.obs_frontend_recording_active() then
        -- Recording already in progress: create a marker file
        start_acting()
    end
end

function script_save(settings)
    debug_print("in script_save")

    local save_array = obs.obs_hotkey_save(hotkey_key1_id)
    obs.obs_data_set_array(settings, "key1_hotkey", save_array)
    obs.obs_data_array_release(save_array)

    save_array = obs.obs_hotkey_save(hotkey_key2_id)
    obs.obs_data_set_array(settings, "key2_hotkey", save_array)
    obs.obs_data_array_release(save_array)
    
    save_array = obs.obs_hotkey_save(hotkey_key3_id)
    obs.obs_data_set_array(settings, "key3_hotkey", save_array)
    obs.obs_data_array_release(save_array)
    
    save_array = obs.obs_hotkey_save(hotkey_key4_id)
    obs.obs_data_set_array(settings, "key4_hotkey", save_array)
    obs.obs_data_array_release(save_array)
end

function script_unload()
    debug_print("in script_unload")
end

function script_defaults(settings)
    debug_print("in script_defaults")
    obs.obs_data_set_default_int(settings, 'Offset', 0)

    obs.obs_data_set_default_bool(settings, 'LogScenes', false)
    obs.obs_data_set_default_int(settings, 'Color0', 0x0080FF)

    obs.obs_data_set_default_string(settings, 'Text1', 'Key1')
    obs.obs_data_set_default_int(settings, 'Color1', 0xFFFF00)

    obs.obs_data_set_default_string(settings, 'Text2', 'Key2')
    obs.obs_data_set_default_int(settings, 'Color2', 0xFF00FF)

    obs.obs_data_set_default_string(settings, 'Text3', 'Key3')
    obs.obs_data_set_default_int(settings, 'Color3', 0x00FFFF)

    obs.obs_data_set_default_string(settings, 'Text4', 'Key4')
    obs.obs_data_set_default_int(settings, 'Color4', 0xFF8000)
end

function script_properties()
    debug_print("in script_properties")

    local props = obs.obs_properties_create()

    local prop = obs.obs_properties_add_int(props, 'Offset',
            'Timestamp Offset (msec)', -10000, 10000, 1)

    prop = obs.obs_properties_add_bool(props, 'LogScenes', 'Mark scene changes')
    prop = obs.obs_properties_add_color(props, 'Color0', '')

    prop = obs.obs_properties_add_text(props, 'Text1',
            'Hotkey 1 Text', obs.OBS_TEXT_DEFAULT)
    prop = obs.obs_properties_add_color(props, 'Color1', '')

    prop = obs.obs_properties_add_text(props, 'Text2',
            'Hotkey 2 Text', obs.OBS_TEXT_DEFAULT)
    prop = obs.obs_properties_add_color(props, 'Color2', '')

    prop = obs.obs_properties_add_text(props, 'Text3',
            'Hotkey 3 Text', obs.OBS_TEXT_DEFAULT)
    prop = obs.obs_properties_add_color(props, 'Color3', '')

    prop = obs.obs_properties_add_text(props, 'Text4',
            'Hotkey 4 Text', obs.OBS_TEXT_DEFAULT)
    prop = obs.obs_properties_add_color(props, 'Color4', '')

    return props
end

function script_update(settings)
    timestamp_offset = obs.obs_data_get_int(settings, 'Offset')

    log_scenes = obs.obs_data_get_bool(settings, 'LogScenes')
    color0 = obs.obs_data_get_int(settings, 'Color0')

    text1 = obs.obs_data_get_string(settings, 'Text1')
    color1 = obs.obs_data_get_int(settings, 'Color1')

    text2 = obs.obs_data_get_string(settings, 'Text2')
    color2 = obs.obs_data_get_int(settings, 'Color2')

    text3 = obs.obs_data_get_string(settings, 'Text3')
    color3 = obs.obs_data_get_int(settings, 'Color3')

    text4 = obs.obs_data_get_string(settings, 'Text4')
    color4 = obs.obs_data_get_int(settings, 'Color4')

    debug_print('in script_update: ' .. timestamp_offset .. ', ' ..
           text1 .. '/' .. color1 .. ', ' ..
           text2 .. '/' .. color2 .. ', ' ..
           text3 .. '/' .. color3 .. ', ' ..
           text4 .. '/' .. color4)
end

-- Create a CSV file and start capturing markers
function start_acting()
    -- Name of the current recording file (OBS 29.0 and later)
    filename = string.gsub(obs.obs_frontend_get_last_recording(), '.mkv', '.csv')
    logfile = io.open(filename, 'w')
    if logfile == nil then
        -- Force a Lua error: show the script log as a visible error indication
        not_a_function("Can't open log file")
    else
        markerNumber = 1
        time_zero = obs.os_gettime_ns()
        logfile:write("#,Name,Start,End,Length,Color\n")
        debug_print("Recording started")
    end
end

function handle_frontend_event(event)
    if (event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED) then
        if log_scenes then
            local scenesource = obs.obs_frontend_get_current_scene()
            if scenesource ~= nil then
                emit_timestamp('Scene: ' .. obs.obs_source_get_name(scenesource), color0)
                obs.obs_source_release(scenesource)
            end
        end

    elseif event == obs.OBS_FRONTEND_EVENT_RECORDING_STARTED then
        start_acting()

	elseif event == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED then
        if logfile ~= nil then
            logfile:close()
            logfile = nil
            debug_print("Recording stopped")
        end
    end
end

function emit_timestamp(a_message, a_color)
    debug_print("in emit_timestamp with " .. a_message)
    if logfile ~= nil then
        now = (obs.os_gettime_ns() - time_zero) / 1000000000
        now = now + (timestamp_offset/1000)

        -- Replace commas with dashes to avoid confusing simple CSV parsers
        -- High byte of color is an alpha, not wanted by our output
        logfile:write( 'M' .. markerNumber .. ',' ..
                       string.gsub(a_message, ',', '-') .. ',' ..
                       string.format("%.3f", now) .. ',,,' ..
                       string.format("%06X", a_color % 0x01000000) .. '\n' )
        markerNumber = markerNumber + 1
    end
end

function log_key1(pressed)
    if pressed then
        emit_timestamp(text1, color1)
    end
end

function log_key2(pressed)
    if pressed then
        emit_timestamp(text2, color2)
    end
end

function log_key3(pressed)
    if pressed then
        emit_timestamp(text3, color3)
    end
end

function log_key4(pressed)
    if pressed then
        emit_timestamp(text4, color4)
    end
end
