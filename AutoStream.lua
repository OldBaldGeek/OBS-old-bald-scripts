-- AutoStream.lua - simple automated streaming

local obs = obslua
local version = '0.6'

-- These names must match the source names used on the control scene
local explainer_source  = 'Automatic Streamer - explainer'
local explainer_actions = 'Automatic Streamer - actions'

-- Edited/persisted values
local command_file = ''             -- from filepath control
local continue_on_error = false     -- from checkbox

-- Interpreter variables
local error_flag = false            -- sticky error flag to stop execution
local command_data = {}             -- array of lines from command file
local command_index = 0             -- line number to execute in command_data
local command_scene = 'none'        -- scene showing our progress
local time_command_started = 0      -- time_t that current command started

  local STATE_STOPPED = 0           -- Not running
  local STATE_PAUSED  = 1           -- Paused: control scene not selected
  local STATE_TRANSITIONING = 2     -- Waiting for transition to complete
  local STATE_RUN     = 3           -- Running
local state = STATE_STOPPED

local timer_interval_ms = 1000      -- timer poll interval
local timer_active = false
local log_lines = '\n\n\n\n\n\n\n\n\n'

-- Table of commands/handlers (initialized by each handler definition)
local cmd_table = {}

-- Description displayed in the Scripts dialog window
function script_description()
    local str = '<h2>AutoStream Version ' .. version ..'</h2>' ..
           [[<p>Use a data file to control automated streaming</p>
           ]]
    return str
end

-- Text for "Explainer" text source. replace "%s" with actual filename
local explainer_text = 
[[When this scene is visible in Preview, commands from
  "%s"
will be executed to select scenes, set audio levels, and begin and end the stream.

If you change Preview to another scene, automatic operation will be paused.
Switching back to this scene will resume automatic operation.]]

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
    print('ERROR: ' .. a_text)

    error_flag = true
    show_text('ERROR: ' .. a_text)
    
    if not continue_on_error then
        set_state(STATE_STOPPED)
        show_text('STOPPED due to error')
    end

    return continue_on_error
end

-- Display a string on the control scene's "actions" source, or log if no such source
function show_text(text, temporary)
    local source = obs.obs_get_source_by_name(explainer_actions)
    if source ~= nil then
        local settings = obs.obs_data_create()

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

        -- The OBS GDI+ source property editor shows #html color as #RRGGBB,
        -- so red=255, green=0, blue=0 is shown as #FF0000
        -- But the saved json gets 4278190335 = 0xFF0000FF, with red as the LAST byte,
        -- and an extra FF on the top. You can edit the json to remove to top FF, and
        -- it reads back just the same.
        -- Lua needs to used this BGR format: red = 255 / 0x0000FF, green = 0x00FF00
        local color = 0x00FF00  -- GREEN
        if error_flag then
            color = 0x0000FF    -- RED
        end
        obs.obs_data_set_int(settings, 'color', color)
        obs.obs_source_update(source, settings)
        obs.obs_source_release(source)
    else
        print(text)
    end
end

-- Display a string on the control scene's "explainer" source
function show_explainer(text)
    local source = obs.obs_get_source_by_name(explainer_source)
    if source ~= nil then
        local settings = obs.obs_data_create()
        obs.obs_data_set_string(settings, 'text', text)
        obs.obs_source_update(source, settings)
        obs.obs_source_release(source)
    end
end

-- Called to set default values of edited/persisted data
-- (Called by framework BEFORE script_load)
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
            retval = entry(tail)
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
            show_text('STOPPED: end of file')
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
    log_lines = '\n\n\n\n\n\n\n\n\n'
    
    if command_file == '' then
        local str = 'No command file to play'
        show_explainer(str)
        print(str)
    else
        local str = string.format(explainer_text, command_file)
        show_explainer(str)

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

cmd_table['show'] =
    function(tail)
        show_text(tail)
        return true
    end

cmd_table['profile'] =
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

-- Not very useful, as it will stop the interpreter if control_scene has been set
cmd_table['preview'] =
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

-- Specify a control scene, or specify 'none' to remove a previously selected
-- control scene
cmd_table['control_scene'] =
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
        show_text('Changed control scene to "' .. tail .. '"')
        return true
    end

-- Usually not needed, as explainer_actions has a default
cmd_table['control_text'] =
    function(tail)
        local text_source = obs.obs_get_source_by_name(tail)
        if text_source == nil then
            return set_error('no source called "' .. tail .. '"')
        end

        explainer_actions = tail
        obs.obs_source_release(text_source)

        print('Changed control text source to "' .. tail .. '"')
        return true
    end

-- Set the Program scene.
-- This triggers a transition, and puts the old Program scene in Preview,
-- which will usually stop the interpreter. We use STATE_TRANSITIONING as a
-- hack until the transition is complete. Do you have a better idea?
cmd_table['program'] =
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

-- This could be used to do things that have no direct API, such as
-- interacting with SimpleSlides.lus to change slides, or hide the slide source.
cmd_table['hotkey'] =
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

cmd_table['ctl_hotkey'] =
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

cmd_table['streamkey'] =
    function(tail)
        local service = obs.obs_frontend_get_streaming_service()
        local key = obs.obs_service_get_key(service)
        -- Doc for obs_frontend_get_streaming_service says "returns new reference", but
        -- calling obs.obs_service_release(service) causes a crash on second get
        show_text( 'Streaming Key is "' .. key .. '"')
        return true
    end

-- Note that the changed time may be saved in the json, affecting future runs
cmd_table['transitiontime'] =
    function(tail)
        show_text('Change transition time to "' .. tail .. '"')
        obs.obs_frontend_set_transition_duration( tonumber(tail) )
        return true
    end

-- Probably not very useful, since it will move the Preview to Program, and
-- Preview will typically be our control scene.
-- There might a be use-case where command_scene = 'none'
cmd_table['transition'] =
    function(tail)
        show_text('Begin Transition, taking ' .. obs.obs_frontend_get_transition_duration() .. ' msec' )
        set_state(STATE_TRANSITIONING)
        obs.obs_frontend_preview_program_trigger_transition()
        return true
    end

cmd_table['audiolevel'] =
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
  
local monther = {January=1, Jan=1, February=2, Feb=2,
                 March=3,   Mar=3, April=4,    Apr=4,
                 May=5,              June=6,     Jun=6,
                 July=7,    Jul=7, August=8,   Aug=8,
                 September=9,Sep=9,October=10, Oct=10,
                 November=11,Nov=11,December=12,Dec=12}

cmd_table['date'] =
    function(tail)
        -- Parse the tail as a date: July 24, 2022
        local month, day, year = tail:match('(%a+)%s+(%d+),*%s*(%d+)')
        day = tonumber(day)
        year = tonumber(year)
        if month and monther[month] and
           (day >= 1) and (day <= 31) and (year >= 2022) and (year <= 2099) then
            -- Simplest is year*10000 + month*100 + day
            -- Numerical COMPARE is good, but subtraction doesn't give #days
            month = monther[month]
            local want_num = year*10000 + month*100 + day

            local now = os.date('*t')
            local now_num = now.year*10000 + now.month*100 + now.day
            if now_num < want_num then
                -- Before the date: wait for it
                show_text('Waiting until ' .. tail, true)
                return false
            elseif now_num == want_num then
                -- On the date: continue
                show_text('Today is ' .. tail)
                return true
            else
                -- After the date: stop processing
                set_state(STATE_STOP)
                show_text('STOPPED: today is after the specified date ' .. tail)
                return false
            end
        else
            return set_error('invalid date "' .. tail .. '"')
        end

        return true
    end

cmd_table['time'] =
    function(tail)
        -- Parse the tail as a time: 8:55
        local hour, minute = tail:match('(%d+):(%d+)')
        if hour then
            local want_num = hour*60 + minute

            local now = os.date('*t')
            local now_num = now.hour*60 + now.min
            if now_num < want_num then
                -- Before the time: wait for it
                show_text('Waiting until ' .. tail .. '. Now ' .. os.date('%H:%M:%S'), true)
                return false
            elseif now_num < want_num + 120 then
                -- Within a plausible window of the desired time
                show_text('Time is on or after ' .. tail)
                return true
            else
                set_state(STATE_STOP)
                show_text('STOPPED: more than two hours after the specified time ' .. tail)
                return false
            end
        else
            return set_error('invalid time "' .. tail .. '"')
        end

        return true
    end

cmd_table['wait'] =
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
        
        show_text('Waited ' .. tail .. ' seconds')
        return true
    end

cmd_table['stop'] =
    function(tail)
        set_state(STATE_STOP)
        show_text('STOPPED by command')
        return false
    end

cmd_table['start_streaming'] =
    function(tail)
        if obs.obs_frontend_streaming_active() then
            show_text('Already streaming')
        else
            obs.obs_frontend_streaming_start()
            show_text('Started streaming')
        end
        return true
    end

cmd_table['stop_streaming'] =
    function(tail)
        if obs.obs_frontend_streaming_active() then
            obs.obs_frontend_streaming_stop()
            show_text('Stopped streaming')
        else
            show_text('Not streaming')
        end

        return true
    end

cmd_table['start_recording'] =
    function(tail)
        if obs.obs_frontend_recording_active() then
            show_text('Already recording')
        else
            obs.obs_frontend_recording_start()
            show_text('Started recording')
        end
        return true
    end

cmd_table['stop_recording'] =
    function(tail)
        if obs.obs_frontend_recording_active() then
            obs.obs_frontend_recording_stop()
            show_text('Stopped recording')
        else
            show_text('Not recording')
        end

        return true
    end
