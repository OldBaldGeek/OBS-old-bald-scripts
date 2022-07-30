-- AutoStream.lua - simple automated streaming

local obs = obslua
local version = "0.5"

-- Edited/persisted values
local command_file = ''             -- from filepath control
local continue_on_error = false     -- from checkbox
local test_string = ''              -- from edit control (testing)

-- Interpreter variables
local error_flag = false            -- sticky error flag to stop execution
local command_data = {}             -- array of lines from command file
local command_index = 0             -- line number to execute in command_data
local command_scene = 'none'        -- scene showing our progress
local command_text  = ''            -- Text source in command_scene for results
local time_command_started = 0      -- time_t that current command started

  local STATE_STOPPED = 0           -- Not running
  local STATE_PAUSED  = 1           -- Paused: control scene not selected
  local STATE_TRANSITIONING = 2     -- Waiting for transition to complete
  local STATE_RUN     = 3           -- Running
local state = STATE_STOPPED

local timer_interval_ms = 1000      -- timer poll interval
local timer_active = false
local log_lines = '1\n2\n3\n4\n5\n6\n7\n8\n9\n\10'

-- Table of commands/handlers (initialized after each handler definition)
local cmd_table = {}

-- Description displayed in the Scripts dialog window
function script_description()
    local str = '<h2>AutoStream Version ' .. version ..'</h2>' ..
           [[<p>Use a data file to control automated streaming</p>
           ]]
    return str
end

-- Set state variable, start or stop timer as appropriate
-- STOPPED  Timer stopped
-- PAUSED   Timer stopped
-- TRANS    Timer running
-- RUN      Timer running
--
function set_state(a_state)
    if (a_state == STATE_RUN) or (a_state == STATE_TRANSITIONING) then
        if not timer_active then
            obs.timer_add(timer_callback, timer_interval_ms)
            timer_active = true
        end
    else
        if timer_active then
            obs.timer_remove(timer_callback)
            timer_active = false
        end
    end

    state = a_state
end

-- Log an error, set error flag
-- this may stop the command interpreter
function set_error(a_text)
    show_text('ERROR: ' .. a_text, true, 0x0000FF) -- RED: see note below
    error_flag = true
    
    if not continue_on_error then
        set_state(STATE_STOPPED)
    end

    return continue_on_error
end


-- The OBS GDI+ source property editor shows #html color as #RRGGBB,
-- so red=255, green=0, blue=0 is shown as #FF0000
-- But the saved json gets 4278190335 = 0xFF0000FF, with red as the LAST byte,
-- and an extra FF on the top. You can edit the json to remove to top FF, and
-- it reads back just the same.
-- Lua needs to used this BGR format: red = 255 / 0x0000FF

-- Display a string on the control scene, or log if no control scene
function show_text(text, temporary, color)
    local source = obs.obs_get_source_by_name(command_text)
    if source ~= nil then
        if color == nil then
            color = 0x00FF00 -- GREEN: see note above
        end

        local old_data = obs.obs_source_get_settings(source)
        local old_color = obs.obs_data_get_int(old_data, 'color')
        obs.obs_data_release(old_data)

        local settings = obs.obs_data_create()
        -- print('Text was ' .. old_color .. ' set "' .. text .. '" ' .. color .. '/' .. 1*color)

        if temporary then
            -- Show existing lines, plus this temporary line
            obs.obs_data_set_string(settings, 'text', log_lines .. '\n' .. text)
        else
            -- Delete an old line, add the new one
            local snip = log_lines:find('\n')
            if snip then
                log_lines = log_lines:sub(snip+1) .. '\n' .. text
            else
                log_lines = log_lines .. '\n' .. text
            end
            obs.obs_data_set_string(settings, 'text', log_lines)
        end

        obs.obs_data_set_int(settings, 'color', 1*color)
        obs.obs_source_update(source, settings)
        obs.obs_source_release(source)
    else
        print(text)
    end
end

-- Called to set default values of edited/persisted data
-- (Oddly, called BEFORE script_load)
function script_defaults(settings)
    print("script_defaults")
end

-- Called at script load
function script_load(settings)
    print("script_load")

    obs.obs_frontend_add_event_callback(handle_frontend_event)
end

-- Called at script unload
function script_unload()
    print("script_unload")
end

-- Called after change of settings including once after script load
function script_update(settings)
    -- print("script_update")
    command_file = obs.obs_data_get_string(settings, "command_file")
    continue_on_error = obs.obs_data_get_bool(settings, "continue_on_error")

    test_string = obs.obs_data_get_string(settings, "test_string")
end

-- Called before data settings are saved
function script_save(settings)
    print("script_save")
end

-- Called to display the properties GUI
function script_properties()
    props = obs.obs_properties_create()

    obs.obs_properties_add_path(props, 'command_file', 'Command file', obs.OBS_PATH_FILE,
                                '*.txt *.*', '')
    obs.obs_properties_add_bool(props, 'continue_on_error', 'Continue on error (else stop)')
    obs.obs_properties_add_button(props, 'restart_button', 'Restart command file',
        function() 
            start_playing('Restart Button pressed')
        end)

    -- Stuff for testing
    obs.obs_properties_add_text(props, 'test_string', 'Test String', 0) --, OBS_TEXT_DEFAULT)
    obs.obs_properties_add_button(props, 'test_button', 'DO TEST STUFF',
        function() 
            if not execute_line(test_string, 0) then
                print('Command "' .. test_string .. '" returned false')
            end

            -- return true to update UI
            return true 
        end)

    return props
end

function handle_frontend_event(event)
    if event == obs.OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED then
        print("OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED")

        if state == STATE_TRANSITIONING then
            if command_scene ~= 'none' then
                -- Done with a transition, which changed the preview scene,
                -- and we are using a command_scene:
                -- Change the preview back to the command_scene
                set_state(STATE_RUN)
                local new_scene = obs.obs_get_scene_by_name(command_scene)
                if new_scene ~= nil then
                    print('End of transition: change preview back to "' .. command_scene .. '"')
                    -- This will cause another entry here, but no action
                    obs.obs_frontend_set_current_preview_scene(obs.obs_scene_get_source(new_scene))
                    obs.obs_scene_release(new_scene)
                end
            else
                print('End of transition, no command_scene' )
                set_state(STATE_RUN)
            end

        elseif command_scene ~= 'none' then
            -- We have a command scene
            -- Get the name of the current preview scene
            local preview_source = obs.obs_frontend_get_current_preview_scene()
            if preview_source ~= nil then
                local preview_scene_name = obs.obs_source_get_name(preview_source)
                obs.obs_source_release(preview_source)

                if preview_scene_name == command_scene then
                    -- Preview changed to command scene: resume command processing
                    set_state(STATE_RUN)
                    print('Preview changed to command_scene: resume processing')
                else
                    -- Preview changed away from command scene: pause command processing
                    set_state(STATE_PAUSED)
                    print('Preview changed away from command_scene: pause processing')
                end
            end
        end

	elseif event == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING then
        -- OBS startup: scenes have been loaded
        start_playing('OBS_FRONTEND_EVENT_FINISHED_LOADING')
    elseif event == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED then
        -- Changed scene collection: scenes have been loaded
        start_playing('OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED')

    elseif event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
        print("OBS_FRONTEND_EVENT_SCENE_CHANGED")
    elseif event == obs.OBS_FRONTEND_EVENT_TRANSITION_STOPPED then
        print("OBS_FRONTEND_EVENT_TRANSITION_STOPPED")
    elseif event == obs.OBS_FRONTEND_EVENT_PROFILE_CHANGED then
        print("OBS_FRONTEND_EVENT_PROFILE_CHANGED")
    elseif event == obs.OBS_FRONTEND_EVENT_EXIT then
        print("OBS_FRONTEND_EVENT_EXIT")
    end
end

-- Execute a_line
-- Return true on successful or complete execution (including empty line)
-- Return false on unknown command, or if handler returns false
function execute_line(a_line, a_line_number)
    retval = true
    if a_line ~= '' then
        local command
        local tail
        local c0, cx = a_line:find(' ')
        if c0 == nil then
            command = a_line
            tail = ''
        else
            command = a_line:sub(1, c0-1)
            tail = a_line:sub(cx):match'^%s*(.*)'
        end

        local entry = cmd_table[command]
        if entry ~=nil then
            retval = entry[2](tail)
        else
            return set_error('Unknown command "' .. a_line .. '" (line ' .. 
                              a_line_number .. ')')
        end
    end
    
    return retval
end

-- Timer callback to execute the next script line
function timer_callback()
    if state == STATE_RUN then
        local line = command_data[command_index]
        if line then
            if execute_line(line, command_index) then
                command_index = command_index + 1
                
                -- Remember when the next command weill start.
                -- (Used by WAIT and similar commands)
                time_command_started = os.time()
            end
        else
            -- End of file
            set_state(STATE_STOP)
            show_text('Stopped at end of file')
        end
    end
end

-- Load and start playing a command file
function start_playing(a_reason)
    print('start_playing: ' .. a_reason)
    
    -- Stop any execution in progress
    set_state(STATE_STOPPED)

    command_scene = 'none'
    error_flag = false
    command_index = 0
    command_data = {}
    log_lines = '1\n2\n3\n4\n5\n6\n7\n8\n9\n10'
    
    if command_file == '' then
        print('No command file to play')
    else
        -- Load the file
        infile = io.open(command_file, 'r')
        if infile == nil then
            set_error('no file "' .. command_file .. '"')
            -- TODO: this should force some visible indication,
            -- probably by forcing a Lua error to show the script log,
            -- since we probably don't have a visible control scene.
            -- Showing in the script UI would also be good.
        else
            for line in infile:lines() do
                -- Omit comments to speed up interpreter
                if line ~= '' and line:find('#') ~= 1 then
                    table.insert(command_data, line)
                end
            end

            infile:close()
            print('Command File ' .. command_file .. ' has ' .. table.getn(command_data) .. ' lines')

            -- Start the timer that plays the commands
            command_scene = 'none'
            command_index = 1
            set_state(STATE_RUN)
        end
    end
end

--------------------------------------------------------------------------------
-- Command Handlers
--------------------------------------------------------------------------------

-- This would be more useful if sent to a file...
cmd_table['help'] = {'print a command list', 
    function(tail)
        local str = ''
        for key, value in pairs(cmd_table) do
            str = str .. key .. '\t' .. value[1] .. '\n'
        end
        
        print(str)
        return true
    end
    }

cmd_table['#'] = {'comment line (ignored)', 
    function(tail)
        print('# ' .. tail)
        return true
    end
    }

cmd_table['show'] = {'show tail in the log', 
    function(tail)
        show_text(tail)
        return true
    end
    }

cmd_table['profile'] = {'Change profile to xxxx', 
    function(tail)
        obs.obs_frontend_set_current_profile(tail)
        local newProfile = obs.obs_frontend_get_current_profile()
        if tail ~= newProfile then
            return set_error('can\'t change profile to "' .. tail ..
                             '". Profile is "' .. newProfile .. '"')
        end

        show_text('Changed profile to "' .. tail .. '"')
        return true
    end
    }

-- Not very useful, as it will stop the interpreter
-- if control_scene has been set
cmd_table['preview'] = {'Change preview to xxxx', 
    function(tail)
        local new_scene = obs.obs_get_scene_by_name(tail)
        if new_scene == nil then
            return set_error('no scene called "' .. tail .. '"')
        end

        show_text('Changed preview scene to "' .. tail .. '"')
        obs.obs_frontend_set_current_preview_scene(obs.obs_scene_get_source(new_scene))
        obs.obs_scene_release(new_scene)
        return true
    end
    }

-- Specify a control scene, or specify 'none' to remove a previously selected
-- control scene
cmd_table['control_scene'] = {'Specify the control scene', 
    function(tail)
        if tail ~= 'none' then
            local new_scene = obs.obs_get_scene_by_name(tail)
            if new_scene == nil then
                return set_error('no scene called "' .. tail .. '"')
            end

            obs.obs_frontend_set_current_preview_scene(obs.obs_scene_get_source(new_scene))
            obs.obs_scene_release(new_scene)
        end

        command_scene = tail
        print('Changed control scene to "' .. tail .. '"')
        return true
    end
    }

cmd_table['control_text'] = {'Text source in control scene on which to show our actions', 
    function(tail)
        local text_source = obs.obs_get_source_by_name(tail)
        if text_source == nil then
            return set_error('no source called "' .. tail .. '"')
        end

        command_text = tail
        obs.obs_source_release(text_source)

        print('Changed control text source to "' .. tail .. '"')
        -- Clean out any text from a previous run
        -- show_text('')
        return true
    end
    }

cmd_table['program'] = {'Change program view to xxxx', 
    function(tail)
        new_scene = obs.obs_get_scene_by_name(tail)
        if new_scene == nil then
            return set_error('no scene called "' .. tail .. '"')
        end
        
        -- Stop interpreting until the transition completes and
        -- we process OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED
        set_state(STATE_TRANSITIONING)

        show_text('Changed program scene to "' .. tail .. '"')
        obs.obs_frontend_set_current_scene(obs.obs_scene_get_source(new_scene))
        obs.obs_scene_release(new_scene)
        return true
    end
    }

cmd_table['hotkey'] = {'Send hotkey xxxx', 
    function(tail)
        show_text('Send hotkey "' .. tail .. '"')

        local combo = obs.obs_key_combination()
        combo.modifiers = 0
        combo.key = obs.obs_key_from_name(tail)
        print(combo.key)
        obs.obs_hotkey_inject_event(combo,false)
        obs.obs_hotkey_inject_event(combo,true)
        obs.obs_hotkey_inject_event(combo,false)
        return true
    end
    }

cmd_table['ctl_hotkey'] = {'Send hotkey Ctrl+xxxx',
    function(tail)
        show_text('Send Ctrl + hotkey "' .. tail .. '"')

        local combo = obs.obs_key_combination()
        combo.modifiers = obs.INTERACT_CONTROL_KEY
        combo.key = obs.obs_key_from_name(tail)
        print(combo.key)
        obs.obs_hotkey_inject_event(combo,false)
        obs.obs_hotkey_inject_event(combo,true)
        obs.obs_hotkey_inject_event(combo,false)
        return true
    end
    }

cmd_table['streamkey'] = {'Show streamkey',
    function(tail)
        local service = obs.obs_frontend_get_streaming_service()

        local name = obs.obs_service_get_name(service)
        local key = obs.obs_service_get_key(service)
        -- obs_frontend_get_streaming_service says "returns new reference", but
        -- calling obs.obs_service_release(service) causes a crash on second get
        show_text( 'Streaming Service is "' .. name .. '"  Streaming Key is "' .. key .. '"')
        return true
    end
    }

cmd_table['transitiontime'] = {'Set transition time to xxxx',
    function(tail)
        show_text('Change transition time to "' .. tail .. '"')
        obs.obs_frontend_set_transition_duration( tonumber(tail) )
        return true
    end
    }

-- Probably not very useful, since it will move the Preview to Program, and
-- Preview will typically be our control scene.
-- There might a be use-case where command_scene = 'none'
cmd_table['transition'] = {'Do transition',
    function(tail)
        show_text('Begin Transition, taking ' .. obs.obs_frontend_get_transition_duration() .. ' msec' )
        set_state(STATE_TRANSITIONING)
        obs.obs_frontend_preview_program_trigger_transition()
        return true
    end
    }

cmd_table['audiolevel'] = {'Set audio level of xxxx to yyy dB',
    function(tail)
        local pos, value = tail:match('()%s+(-*%d+)$')
        if pos == nil or value == nil then
            return set_error('cannot parse "' .. tail .. '"')
        end
        
        local source_name = tail:sub(1,pos-1)
        local source = obs.obs_get_source_by_name(source_name)
        if source == nil then
            return set_error('no audio source "' .. source_name .. '"')
        end
        show_text('Set audio level of "' .. source_name .. '" to ' .. value .. ' dB')

        volume = 10.0 ^ (value/20)
        if volume > 1.0 then
            volume = 1.0
        end
        obs.obs_source_set_volume(source, volume)
        obs.obs_source_set_muted(source, false)

        obs.obs_source_release(source)
        return true
    end
    }
  
local monther = {January=1, Jan=1, February=2, Feb=2,
                 March=3,   Mar=3, April=4,    Apr=4,
                 May=5,              June=6,     Jun=6,
                 July=7,    Jul=7, August=8,   Aug=8,
                 September=9,Sep=9,October=10, Oct=10,
                 November=11,Nov=11,December=12,Dec=12}

cmd_table['date'] = {'Wait for specified date',
    function(tail)
        -- Parse the tail as a date: July 24, 2022
        local month, day, year = tail:match('(%a+)%s+(%d+),*%s*(%d+)')
        if month and monther[month] then
            -- Simplest is year*10000 + month*100 + day
            -- Numerical COMPARE is good, but subtraction doesn't give #days
            month = monther[month]
            local want_num = year*10000 + month*100 + day

            local now = os.date('*t')
            local now_num = now.year*10000 + now.month*100 + now.day
            if now_num < want_num then
                -- Before the date: wait for it
                show_text('Waiting for ' .. tail, true)
                return false
            elseif now_num == want_num then
                -- On the date: continue
                show_text('Today is ' .. tail)
                return true
            else
                -- After the date: stop processing
                show_text('After ' .. tail .. '. Stop processing commands')
                set_state(STATE_DONE)
                return false
            end
        else
            return set_error('invalid date "' .. tail .. '"')
        end

        return true
    end
    }

cmd_table['time'] = {'Wait for specified clock time',
    function(tail)
        -- Parse the tail as a time: 8:55
        local hour, minute = tail:match('(%d+):(%d+)')
        if hour then
            local want_num = hour*60 + minute

            local now = os.date('*t')
            local now_num = now.hour*60 + now.min
            if now_num < want_num then
                -- Before the time: wait for it
                show_text('Waiting for ' .. tail .. '. Now ' .. os.date('%H:%M:%S'), true)
                return false
            elseif now_num < want_num + 120 then
                -- Within a plausible window of the desired time
                show_text('On or after ' .. tail)
            else
                show_text('More than two hours after ' .. tail .. '. Stop processing commands')
                set_state(STATE_DONE)
                return false
            end
        else
            return set_error('invalid time "' .. tail .. '"')
        end

        return true
    end
    }

cmd_table['wait'] = {'Wait for specified number of seconds',
    function(tail)
        local sec = tail:match('(%d+)')
        if sec == nil then
            return set_error('invalid time "' .. tail .. '"')
        end

        local delta = os.time() - time_command_started
        if delta < 1*sec then
            show_text('Waiting ' .. sec .. ' seconds: ' .. delta, true)
            return false
        end
        
        show_text('Waited ' .. tail)
        return true
    end
    }

cmd_table['stop'] = {'Stop execution',
    function(tail)
        -- show_text('Stopped')
        print('Stopped')
        set_state(STATE_STOP)
        return false
    end
    }

cmd_table['start_streaming'] = {'Start streaming',
    function(tail)
        if obs.obs_frontend_streaming_active() then
            show_text('Already streaming')
        else
            obs.obs_frontend_streaming_start()
            show_text('Started streaming')
        end
        return true
    end
    }

cmd_table['stop_streaming'] = {'Stop streaming',
    function(tail)
        if obs.obs_frontend_streaming_active() then
            obs.obs_frontend_streaming_stop()
            show_text('Stopped streaming')
        else
            show_text('Not streaming')
        end

        return true
    end
    }

cmd_table['start_recording'] = {'Start recording',
    function(tail)
        if obs.obs_frontend_recording_active() then
            show_text('Already recording')
        else
            obs.obs_frontend_recording_start()
            show_text('Started recording')
        end
        return true
    end
    }

cmd_table['stop_recording'] = {'Stop recording',
    function(tail)
        if obs.obs_frontend_recording_active() then
            obs.obs_frontend_recording_stop()
            show_text('Stopped recording')
        else
            show_text('Not recording')
        end

        return true
    end
    }

-- TODO: just a test bed for color spec
cmd_table['color'] = {'Set color',
    function(tail)
        print('Text color is ' .. tail, tail)
        show_text('Text color is ' .. tail, tail)

        return true
    end
    }

