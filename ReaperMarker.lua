obs = obslua

local program_name = "ReaperMarker"
local version = "1.0"

-- Set true to get debug printing
local debug_print_enabled = false

-- Edited/persisted items
local timestamp_offset = 0
local text1 = 'K1'
local text2 = 'K2'
local text3 = 'K3'
local text4 = 'K4'

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
           <p>When a recording is active, use hot keys to generate timestamped
           markers to facilitate audio editing in Reaper.</p>
           <p>Output is a CSV file that may be imported in Reaper via "View",
           "Region/Marker Manager", "Import..."</p>
           <p>NOTE: set Reaper timeline format to "Seconds" before importing.</p>
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
    obs.obs_data_set_default_string(settings, 'Text1', 'Room')
    obs.obs_data_set_default_string(settings, 'Text2', 'Presenter')
    obs.obs_data_set_default_string(settings, 'Text3', 'Key3')
    obs.obs_data_set_default_string(settings, 'Text4', 'Key4')
end

function script_properties()
    debug_print("in script_properties")

    local props = obs.obs_properties_create()

    local prop = obs.obs_properties_add_int(props, 'Offset', 'Timestamp Offset (msec)',
            -10000, 10000, 1)
    prop = obs.obs_properties_add_text(props, 'Text1',
            'Key 1 Text', obs.OBS_TEXT_DEFAULT)
    prop = obs.obs_properties_add_text(props, 'Text2',
            'Key 2 Text', obs.OBS_TEXT_DEFAULT)
    prop = obs.obs_properties_add_text(props, 'Text3',
            'Key 3 Text', obs.OBS_TEXT_DEFAULT)
    prop = obs.obs_properties_add_text(props, 'Text4',
            'Key 4 Text', obs.OBS_TEXT_DEFAULT)

    return props
end

function script_update(settings)
    timestamp_offset = obs.obs_data_get_int(settings, 'Offset')
    text1 = obs.obs_data_get_string(settings, 'Text1')
    text2 = obs.obs_data_get_string(settings, 'Text2')
    text3 = obs.obs_data_get_string(settings, 'Text3')
    text4 = obs.obs_data_get_string(settings, 'Text4')

    print('in script_update: ' .. timestamp_offset .. ',' .. text1 ..
          ',' .. text2 .. ',' .. text3 .. ',' .. text4 )
end

function handle_frontend_event(event)
    if event == obs.OBS_FRONTEND_EVENT_RECORDING_STARTED then
        local prof = obs.obs_frontend_get_profile_config()
        if prof then
            -- Default something like C:\\Users\\ewe\\Videos
            local path = obs.config_get_string(prof, "AdvOut", "RecFilePath")
            debug_print("Recording to " .. path)

            -- Default is %CCYY-%MM-%DD %hh-%mm-%ss
            local name = obs.config_get_string(prof, "Output", "FilenameFormatting")
            debug_print("Name format " .. name)
            
            -- Format comes in like %CCYY-%MM-%DD %hh-%mm-%ss and resolves to all numeric values,
            -- while os.data would want %Y-%m-%d %H-%M-%S
            -- We use a rock as a hammer, and cuss the lack of a non-pattern substitution in Lua
            local timestamp = os.date("*t")
            name = string.gsub(name, "%%", "X")
            name = string.gsub(name, "XCCYY", timestamp['year'])
            name = string.gsub(name, "XMM", string.format( "%02d", timestamp['month']))
            name = string.gsub(name, "XDD", string.format( "%02d", timestamp['day']))
            name = string.gsub(name, "Xhh", string.format( "%02d", timestamp['hour']))
            name = string.gsub(name, "Xmm", string.format( "%02d", timestamp['min']))
            name = string.gsub(name, "Xss", string.format( "%02d", timestamp['sec']))
            local filename = path .. '\\' .. name .. '.csv'
            debug_print("Creating logfile: " .. filename)

            logfile = io.open(filename, 'w')
            if logfile == nil then
                -- Force a visible indication by forcing a Lua error
                -- to show the script log.
                not_a_function("Can't open log file")
            else
                markerNumber = 1
                time_zero = obs.os_gettime_ns()
                logfile:write("#,Name,Start,End,Length\n")
                debug_print("Recording started")
            end
        end

	elseif event == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED then
        if logfile ~= nil then
            logfile:close()
            logfile = nil
            debug_print("Recording stopped")
        end
    end
end

function emit_timestamp(a_message)
    debug_print("in emit_timestamp with " .. a_message)
    if logfile ~= nil then
        now = (obs.os_gettime_ns() - time_zero) / 1000000000
        now = now + (timestamp_offset/1000)
        logfile:write( 'M' .. markerNumber .. ',' .. a_message .. ',' .. 
                       string.format( "%.3f", now) .. ',,\n' )
        markerNumber = markerNumber + 1
    end
end

function log_key1(pressed)
    if pressed then
        emit_timestamp(text1)
    end
end

function log_key2(pressed)
    if pressed then
        emit_timestamp(text2)
    end
end

function log_key3(pressed)
    if pressed then
        emit_timestamp(text3)
    end
end

function log_key4(pressed)
    if pressed then
        emit_timestamp(text4)
    end
end
