-- AutoStream.lua - simple automated streaming

local obs = obslua
local version = "0.2"

-- Edited/persisted values
local test_string = ''

function cmd_profile(tail)
    obs.obs_frontend_set_current_profile(tail)
    local newProfile = obs.obs_frontend_get_current_profile()
    if tail == newProfile then
        print('Change profile to "' .. tail .. '"')
    else
        print('Can\'t change profile to "' .. tail ..
              '". Profile is "' .. newProfile .. '"')
    end
end

function cmd_preview(tail)
    new_scene = obs.obs_get_scene_by_name(tail)
    if new_scene == nil then
        print('No scene called "' .. tail .. '"')
    else
        print('Change preview scene to "' .. tail .. '"')
        obs.obs_frontend_set_current_preview_scene( obs.obs_scene_get_source(new_scene))
        obs.obs_scene_release(new_scene)
    end
end

function cmd_program(tail)
    new_scene = obs.obs_get_scene_by_name(tail)
    if new_scene == nil then
        print('No scene called "' .. tail .. '"')
    else
        print('Change program scene to "' .. tail .. '"')
        obs.obs_frontend_set_current_scene( obs.obs_scene_get_source(new_scene))
        obs.obs_scene_release(new_scene)
    end
end

function cmd_hotkey(tail)
    print('Send hotkey "' .. tail .. '"')

    local combo = obs.obs_key_combination()
    combo.modifiers = 0
    combo.key = obs.obs_key_from_name(tail)
    print(combo.key)
    obs.obs_hotkey_inject_event(combo,false)
    obs.obs_hotkey_inject_event(combo,true)
    obs.obs_hotkey_inject_event(combo,false)
end

function cmd_ctl_hotkey(tail)
    print('Send Ctrl + hotkey "' .. tail .. '"')

    local combo = obs.obs_key_combination()
    combo.modifiers = obs.INTERACT_CONTROL_KEY
    combo.key = obs.obs_key_from_name(tail)
    print(combo.key)
    obs.obs_hotkey_inject_event(combo,false)
    obs.obs_hotkey_inject_event(combo,true)
    obs.obs_hotkey_inject_event(combo,false)
end

function cmd_streamkey(tail)
    local service = obs.obs_frontend_get_streaming_service()

    local name = obs.obs_service_get_name(service)
    local key = obs.obs_service_get_key(service)
    -- obs_frontend_get_streaming_service says "returns new reference", but
    -- calling obs.obs_service_release(service) causes a crash on second get
    print( 'Service is "' .. name .. '"  Key is "' .. key .. '"')
end

function cmd_transitiontime(tail)
    print('Change transition time to "' .. tail .. '"')
    obs.obs_frontend_set_transition_duration( tonumber(tail) )
end

function cmd_transition(tail)
    print('Transition, taking ' .. obs.obs_frontend_get_transition_duration() .. ' msec' )
    obs.obs_frontend_preview_program_trigger_transition()
end

function cmd_audiolevel(tail)
    local pos, spc, value = tail:match('()(%s+)(-*%d+)$')
    if pos ~= nil and value ~= nil then
        local source_name = tail:sub(1,pos-1)
        local source = obs.obs_get_source_by_name(source_name)
        if source then
            print('Set audio level of "' .. source_name .. '" to ' .. value .. ' dB')

            volume = 10.0 ^ (value/20)
            if volume > 1.0 then
                volume = 1.0
            end

            obs.obs_source_set_volume(source, volume)
            obs.obs_source_release(source)
        else
            print('No audio source "' .. source_name .. '"')
        end
    end
end

function cmd_date(tail)
    -- seconds 1658696886
    local text = os.time()
    print('raw time ' .. text)

    -- Sun Jul 24 16:08:06 2022
    text = os.date()
    print('raw date' .. text)
    
    -- July 24, 2022.  16:08:06
    text = os.date('%B %d, %Y.  %H:%M:%S')
    print('formatted ' .. text)

    local now = os.date('*t')
    print('table ' .. now.year .. ' ' .. now.month .. ' ' .. now.day)
    print('      ' .. now.hour .. ':' .. now.min .. ':' .. now.sec)
end

function cmd_readfile(tail)
    path = script_path() .. tail
    infile = io.open(path, 'r')
    if infile then
        print("Reading " .. path)
        local raw = infile:read("*a")
        infile:close()
        print(raw)
    else
        print('No file "' .. path .. '"')
    end
end


-- Table of commands
local cmd_table = {}
cmd_table['profile']        = {'Change profile to xxxx', cmd_profile}
cmd_table['preview']        = {'Change preview to xxxx', cmd_preview}
cmd_table['program']        = {'Change program to xxxx', cmd_program}
cmd_table['hotkey']         = {'Send hotkey xxxx',       cmd_hotkey}
cmd_table['ctl_hotkey']     = {'Send hotkey Ctrl+xxxx',  cmd_ctl_hotkey}
cmd_table['streamkey']      = {'Show streamkey',         cmd_streamkey}
cmd_table['transitiontime'] = {'Set transition time to xxxx', cmd_transitiontime}
cmd_table['transition']     = {'Do transition',               cmd_transition}
cmd_table['audiolevel']     = {'Set audio level of xxxx to yyy dB', cmd_audiolevel}
cmd_table['date']           = {'Play with date and time',     cmd_date}
cmd_table['readfile']       = {'Read file xxxx',         cmd_readfile}

-- Description displayed in the Scripts dialog window
function script_description()
    local str = '<h2>AutoStream Version ' .. version ..'</h2>' ..
           [[<p>Use a data file to control automated streaming</p>
             <dl>
           ]]

    for key, value in pairs(cmd_table) do
        str = str .. '<dt>' .. key .. '</dt><dd>' .. value[1] .. '</dd>'
    end

    return str .. '</dl>'
end

-- Called at script load
function script_load(settings)
    print("script_load")
end

-- Called at script unload
function script_unload()
    print("script_unload")
end

-- Called to set default values of data settings
function script_defaults(settings)
    print("script_defaults")
end

-- Called to display the properties GUI
function script_properties()
    props = obs.obs_properties_create()

    -- Stuff for testing
    obs.obs_properties_add_text(props, "test_string", "Test String", 0) --, OBS_TEXT_DEFAULT)
    obs.obs_properties_add_button(props, "test_button", "DO TEST STUFF",
        function() 
            if test_string ~= '' then
                local command
                local tail
                local c0, cx = test_string:find(' ')
                if c0 == nil then
                    command = test_string
                    tail = ''
                else
                    command = test_string:sub(1, c0-1)
                    tail = test_string:sub(cx):match'^%s*(.*)'
                    print('Command="' .. command .. '" tail="' .. tail .. '"')
                end

                -- Make sure this can work on a timer callback
                -- command_proc(command, tail)
                -- delayed_command(command, tail)

                local entry = cmd_table[command]
                if entry ~=nil then
                    print('Command "' .. entry[1] .. '"')
                    entry[2](tail)
                else
                    print('Unknown command "' .. command .. '"')
                end

            end

            return true 
        end)

    return props
end

local timed_command = nil
local timed_tail = nil
function delayed_command(command, tail)
    timed_command = command
    timed_tail = tail
    obs.timer_add(timer_callback, 2000)
end

function timer_callback()
    if timed_command ~= nil then
        print('timer_callback')
        obs.remove_current_callback()
        command_proc(timed_command, timed_tail)
        timed_command = nil
    end
end

-- Called after change of settings including once after script load
function script_update(settings)
    -- print("script_update")
    test_string = obs.obs_data_get_string(settings, "test_string")
end

-- Called before data settings are saved
function script_save(settings)
    print("script_save")
end
