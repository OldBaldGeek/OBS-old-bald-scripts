-- AutoStream.lua - simple automated streaming

local obs = obslua
local version = '1.6'

-- These names must match the source names used on the control scene
local explainer_source  = 'Automatic Streamer - explainer'
local explainer_actions = 'Automatic Streamer - actions'

-- Edited/persisted values
local command_file = ''             -- from filepath control
local continue_on_error = false     -- from checkbox

-- Interpreter variables
local error_flag = false            -- sticky error flag to stop execution
local command_data = {}             -- array of lines from command file
local command_index = 0             -- index into command_data
local command_scene = 'none'        -- scene showing our progress
local time_command_started = 0      -- time_t that current command started
local label_to_index = {}           -- map between label and command index

  local STATE_STOPPED = 0           -- Not running
  local STATE_PAUSED  = 1           -- Paused: control scene not selected
  local STATE_TRANSITIONING = 2     -- Waiting for transition to complete
  local STATE_RUN     = 3           -- Running
local state = STATE_STOPPED

local timer_interval_ms = 1000      -- timer poll interval
local timer_active = false
local callback_active = false
local clean_log_lines = '\n\n\n\n\n\n\n\n\n\n\n\n\n'
local log_lines = clean_log_lines

local time_late_limit_minutes = 60  -- minutes after "time" to assume same event

-- Return codes from command handlers
local IMMEDIATE_NEXT = 0    -- execute the next command immediately
local DELAYED_NEXT   = 1    -- execute the next command on the next tick
local DELAYED_SAME   = 2    -- execute the same command on the next tick

-- Table of commands/handlers (initialized by each handler definition)
local cmd_table = {}

-- Script variables set by "$varname =" commands, used as command parameters elsewhere
local variables = {}

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
--   STOPPED  Timer stopped
--   PAUSED   Timer stopped
--   TRANS    Timer running
--   RUN      Timer running
function set_state(a_state)
    if (a_state == STATE_RUN) or (a_state == STATE_TRANSITIONING) then
        if not timer_active then
            obs.timer_add(timer_callback, timer_interval_ms)
            timer_active = true
        end

        if not callback_active then
            obs.obs_frontend_add_event_callback(handle_frontend_event)
            callback_active = true
        end

    elseif (a_state == STATE_STOP) and callback_active then
        obs.obs_frontend_remove_event_callback(handle_frontend_event)
        callback_active = false
    else
        if timer_active then
            obs.timer_remove(timer_callback)
            timer_active = false
        end
    end

    state = a_state
end

-- Log an error, set error flag
-- This may stop the command interpreter
function set_error(a_text)
    print('ERROR: ' .. a_text)

    error_flag = true
    show_text('ERROR: ' .. a_text)
    
    if not continue_on_error then
        set_state(STATE_STOPPED)
        show_text('STOPPED due to error')
    end

    if continue_on_error then
        return DELAYED_NEXT
    end
    return DELAYED_SAME
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
            print('show_text: ' .. text)
        end

        -- The OBS GDI+ source property editor shows #html color as #RRGGBB,
        -- so red=255, green=0, blue=0 is shown as #FF0000
        -- But the saved json gets 4278190335 = 0xFF0000FF, with red as the LAST byte,
        -- and an extra FF on the top. You can edit the json to remove to top FF, and
        -- it reads back just the same.
        -- Lua needs to use this BGR format: red = 255 / 0x0000FF, green = 0x00FF00
        local color = 0x00FF00  -- GREEN
        if error_flag then
            color = 0x0000FF    -- RED
        end
        obs.obs_data_set_int(settings, 'color', color)
        obs.obs_source_update(source, settings)
        obs.obs_data_release(settings)
        obs.obs_source_release(source)
    else
        print('show_text: ' .. text)
    end
end

-- Display a string on the control scene's "explainer" source
function show_explainer(text)
    local source = obs.obs_get_source_by_name(explainer_source)
    if source ~= nil then
        local settings = obs.obs_data_create()
        obs.obs_data_set_string(settings, 'text', text)
        obs.obs_source_update(source, settings)
        obs.obs_data_release(settings)
        obs.obs_source_release(source)
    end
end

-- Called to set default values of edited/persisted data
-- (Called by framework BEFORE script_load)
function script_defaults(settings)
    -- print("script_defaults")
end

-- Called at script load
function script_load(settings)
    print("script_load")

    -- Connect callback to handle OBS_FRONTEND_EVENT_FINISHED_LOADING
    -- and kick off the script
    obs.obs_frontend_add_event_callback(handle_frontend_event)
    callback_active = true
end

-- Called at script unload
function script_unload()
    -- print("script_unload")
end

-- Called after change of settings including once after script load
function script_update(settings)
    -- print("script_update")
    command_file = obs.obs_data_get_string(settings, "command_file")
    continue_on_error = obs.obs_data_get_bool(settings, "continue_on_error")
end

-- Called before data settings are saved
function script_save(settings)
    -- print("script_save")
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
        -- print("OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED")

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

-- Process a command tail to expand any $variables
function expand_tail(a_tail)
    local retval = ''
    local start = 1
    while true do
        local ix, jx = a_tail:find('%$[%w_]+', start)
        if ix ~= nil then
            -- Found a variable name
            if ix > start then
                -- Copy preceding text
                retval = retval .. a_tail:sub(start, ix-1)
            end

            local var = a_tail:sub(ix+1, jx)
            local value = variables[var]
            if value == nil then
                set_error('unknown variable "' .. var .. '" in command tail "' .. 
                          a_tail .. '"')
                -- Not clear what to return here. Hope that empty tail will
                -- cause our caller to generate an error and stop.
                return ''
            end
            retval = retval .. value
            start = jx+1
        else
            -- No more variables to expand
            retval = retval .. a_tail:sub(start, -1)
            break
        end
    end

    return retval
end

-- Execute a_line
-- Returns the result code from the command handler:
--   IMMEDIATE_NEXT to execute the next command immediately
--   DELAYED_NEXT   to execute the next command on the next tick
--   DELAYED_SAME   to execute the same command on the next tick
--
-- Return DELAYED_NEXT on set-variable or empty line
--
function execute_line(a_line, a_line_number)
    local retval = IMMEDIATE_NEXT
    if a_line:sub(1,1) == '$' then
        -- Variable assignment
        local varname, value = a_line:match('%$([%w_]+)%s*%=%s*(.+)')
        if varname == nil or value == nil then
            return set_error('cannot parse "' .. (a_line or '') .. '" as assignment (line ' ..
                              a_line_number .. ')')
        end
        show_text('  ' .. varname .. ' is ' .. value)
        variables[varname] = value

    elseif a_line ~= '' then
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
            retval = entry( expand_tail(tail) )
        else
            return set_error('unknown command "' .. a_line .. '" (line ' .. 
                              a_line_number .. ')')
        end
    end
    
    return retval
end

-- Timer callback to execute the next script line
function timer_callback()
    local retval = IMMEDIATE_NEXT
    while (state == STATE_RUN) and (retval == IMMEDIATE_NEXT) do
        local line = command_data[command_index]
        if line then
            retval = execute_line(line, command_index)
            if retval ~= DELAYED_SAME then
                command_index = command_index + 1
                
                -- Remember when the next command will start.
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
    log_lines = clean_log_lines
    
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
            this_is_not_a_function()
        else
            local index = 1
            for line in infile:lines() do
                -- Omit comments to speed up interpreter
                if line ~= '' and line:find('#') ~= 1 then
                    if line:find(':') == 1 then
                        -- Code label: map to index of next command
                        label_to_index[line:sub(2)] = index
                        -- print('Label "' .. line:sub(2) .. '" index ' .. index)
                    else
                        table.insert(command_data, line)
                        index = index + 1
                    end
                end
            end

            infile:close()
            -- print('Command File ' .. command_file .. ' has ' .. table.getn(command_data) .. ' lines')

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

-- Display the command tail
cmd_table['show'] =
    function(tail)
        show_text(tail)
        return IMMEDIATE_NEXT
    end

-- Show current OBS profile
-- OPTIONS:
-- * no tail: show profile
-- * tail and "else": match profile, goto if no match
-- * tail, no "else": match profile, ERROR if no match?
-- * "else" alone: syntax error
cmd_table['profile'] =
    function(tail)
        local current_profile = obs.obs_frontend_get_current_profile()
        show_text('Current profile is "' .. current_profile .. '"')

        local desired_profile = tail:match('(.+)%s+else')
        if desired_profile ~= nil then
            if current_profile ~= desired_profile then
                -- Current profile doesn't match desired: take the "else"
                goto_label(tail)
            end
        elseif (tail ~= '') and (current_profile ~= tail) then
            return set_error('expected profile "' .. tail ..
                             '", but profile is "' .. current_profile .. '"')
        end

        return IMMEDIATE_NEXT
    end

-- Set OBS profile, mostly to change the streaming key
cmd_table['set_profile'] =
    function(tail)
        obs.obs_frontend_set_current_profile(tail)
        -- An immediate call to obs_frontend_get_current_profile may return
        -- the PREVIOUS profile. Follow "profile" with a short delays and
        -- "show_profile" to verify the profile change

        show_text('Changed profile to "' .. tail .. '"')
        return DELAYED_NEXT
    end

-- Set the Preview scene.
-- Not very useful, as it will stop the interpreter if control_scene has been set
cmd_table['preview'] =
    function(tail)
        local new_scene = obs.obs_get_scene_by_name(tail)
        if new_scene == nil then
            return set_error('no preview scene called "' .. (tail or '') .. '"')
        end

        show_text('Changed preview scene to "' .. tail .. '"')
        obs.obs_frontend_set_current_preview_scene(obs.obs_scene_get_source(new_scene))
        obs.obs_scene_release(new_scene)
        return DELAYED_NEXT
    end

-- Specify a control scene, or specify 'none' to remove a previously selected
-- control scene
cmd_table['control_scene'] =
    function(tail)
        if tail ~= 'none' then
            local new_scene = obs.obs_get_scene_by_name(tail)
            if new_scene == nil then
                return set_error('no control scene called "' .. (tail or '') .. '"')
            end

            obs.obs_frontend_set_current_preview_scene(obs.obs_scene_get_source(new_scene))
            obs.obs_scene_release(new_scene)
        end

        command_scene = tail
        show_text('  Changed control scene to "' .. tail .. '"')
        return DELAYED_NEXT
    end

-- Specify the GDI text source to be used to show control actions.
-- Usually not needed, as explainer_actions has a default
cmd_table['control_text'] =
    function(tail)
        local text_source = obs.obs_get_source_by_name(tail)
        if text_source == nil then
            return set_error('no text source called "' .. (tail or '') .. '"')
        end

        explainer_actions = tail
        obs.obs_source_release(text_source)
        print('  Changed control text source to "' .. tail .. '"')
        return DELAYED_NEXT
    end

-- Set the Program scene.
-- This triggers a transition, and puts the old Program scene in Preview,
-- which will usually stop the interpreter. We use STATE_TRANSITIONING as a
-- hack until the transition is complete. Do you have a better idea?
cmd_table['program'] =
    function(tail)
        new_scene = obs.obs_get_scene_by_name(tail)
        if new_scene == nil then
            return set_error('no program scene called "' .. (tail or '') .. '"')
        end
        
        -- Stop interpreting until the transition completes and
        -- we process OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED
        set_state(STATE_TRANSITIONING)

        show_text('Changed program scene to "' .. tail .. '"')
        obs.obs_frontend_set_current_scene(obs.obs_scene_get_source(new_scene))
        obs.obs_scene_release(new_scene)
        return DELAYED_NEXT
    end

-- Generate a hotkey press and release
-- This could be used to do things that have no direct API, such as
-- interacting with SimpleSlides.lus to change slides, or hide the slide source.
cmd_table['hotkey'] =
    function(tail)
        local combo = obs.obs_key_combination()
        combo.modifiers = 0
        combo.key = obs.obs_key_from_name(tail)
        -- print(combo.key)
        obs.obs_hotkey_inject_event(combo,false)
        obs.obs_hotkey_inject_event(combo,true)
        obs.obs_hotkey_inject_event(combo,false)
        show_text('  Sent hotkey "' .. tail .. '"')
        return DELAYED_NEXT
    end

cmd_table['ctl_hotkey'] =
    function(tail)
        local combo = obs.obs_key_combination()
        combo.modifiers = obs.INTERACT_CONTROL_KEY
        combo.key = obs.obs_key_from_name(tail)
        -- print(combo.key)
        obs.obs_hotkey_inject_event(combo,false)
        obs.obs_hotkey_inject_event(combo,true)
        obs.obs_hotkey_inject_event(combo,false)
        show_text('  Sent Ctrl + hotkey "' .. tail .. '"')
        return DELAYED_NEXT
    end

-- Show the current streaming key
cmd_table['show_streamkey'] =
    function(tail)
        local service = obs.obs_frontend_get_streaming_service()
        local key = obs.obs_service_get_key(service)
        -- Doc for obs_frontend_get_streaming_service says "returns new reference", but
        -- calling obs.obs_service_release(service) causes a crash on second get
        show_text( 'Current Streaming Key is "' .. key .. '"')
        return IMMEDIATE_NEXT
    end

-- Specify the duration of the default transition.
-- Note that the changed time may be saved in the json, affecting future runs
cmd_table['transitiontime'] =
    function(tail)
        obs.obs_frontend_set_transition_duration( tonumber(tail) )
        show_text('  Changed transition time to "' .. tail .. '"')
        return IMMEDIATE_NEXT
    end

-- Cause a transition.
-- Probably not very useful, since it will move the Preview to Program, and
-- Preview will typically be our control scene.
-- There might a be use-case where command_scene = 'none'
cmd_table['transition'] =
    function(tail)
        show_text('  Begin Transition lasting ' .. obs.obs_frontend_get_transition_duration() .. ' msec' )
        set_state(STATE_TRANSITIONING)
        obs.obs_frontend_preview_program_trigger_transition()
        return DELAYED_NEXT
    end

-- Set the level of an audio source
cmd_table['audiolevel'] =
    function(tail)
        local pos, value = tail:match('()%s+(-*%d+)$')
        if pos == nil or value == nil then
            return set_error('audiolevel cannot parse "' .. (tail or '') .. '"')
        end
        
        local source_name = tail:sub(1,pos-1)
        local source = obs.obs_get_source_by_name(source_name)
        if source == nil then
            return set_error('no audio source "' .. (source_name or '') .. '"')
        end
        show_text('  Set audio level of "' .. source_name .. '" to ' .. value .. ' dB')

        volume = 10.0 ^ (value/20)
        if volume > 1.0 then
            volume = 1.0
        end
        obs.obs_source_set_volume(source, volume)
        obs.obs_source_set_muted(source, false)

        obs.obs_source_release(source)
        return IMMEDIATE_NEXT
    end

-- If a_tail contains "else {label}", set command_index per label
-- Else stop the interpreter
function goto_label(a_tail)
    local label = a_tail:match('.+%s+else%s+([%w_]+)')
    if label then
        if label_to_index[label] then
            command_index = label_to_index[label] - 1
            show_text('  Jump to ' .. label .. ' (' .. command_index + 1 .. ')')
            return IMMEDIATE_NEXT
        end
    end

    set_state(STATE_STOP)
    show_text('STOPPED (no label)')
    return DELAYED_SAME
end

-- GOTO label
cmd_table['goto'] =
    function(tail)
        if tail and label_to_index[tail] then
            command_index = label_to_index[tail] - 1
            show_text('  Jump to ' .. tail .. ' (' .. command_index + 1 .. ')')
            return IMMEDIATE_NEXT
        end
        return set_error('invalid goto "' .. (tail or '') .. '"')
    end

local monther = {January=1,  Jan=1, February=2, Feb=2,
                 March=3,    Mar=3, April=4,    Apr=4,
                 May=5,             June=6,     Jun=6,
                 July=7,     Jul=7, August=8,   Aug=8,
                 September=9,Sep=9, October=10, Oct=10,
                 November=11,Nov=11,December=12,Dec=12}

local legal_days = {ANY=true, MONDAY=true, TUESDAY=true, WEDNESDAY=true,
                    THURSDAY=true, FRIDAY=true, SATURDAY=true, SUNDAY=true}

-- Verify or wait for the specified date
cmd_table['date'] =
    function(tail)
        -- Parse the tail as a date: July 24, 2022
        local ix, iy, month, day, year = tail:find('(%a+)%s+(%d+),*%s*(%d+)')
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
                show_text('  Waiting until ' .. tail:sub(ix,iy), true)
                return DELAYED_SAME
            elseif now_num == want_num then
                -- On the date: continue
                show_text('Today is ' .. tail:sub(ix,iy))
                return IMMEDIATE_NEXT
            else
                -- After the date: goto label (if any), or stop processing
                show_text('Today is after the specified date ' .. tail:sub(ix,iy))
                return goto_label(tail)
            end
        else
            -- Not a date. Is it a day of the week, or 'ANY'?
            local ix, iy, want_day = tail:find('(%a+)')
            if want_day and legal_days[string.upper(want_day)] then
                local now_day = string.upper(os.date('%A'))
                want_day = string.upper(want_day)
                if (want_day == 'ANY') or (now_day == want_day) then
                    -- On the date: continue
                    show_text('Today is ' .. now_day)
                    return IMMEDIATE_NEXT
                else
                    local label = tail:match('.+%s+else%s+([%w_]+)')
                    if label then
                        -- not today: take the else
                        show_text('Today is not ' .. want_day)
                        return goto_label(tail)
                    else
                        -- not today: wait for it
                        show_text('  Waiting until ' .. want_day, true)
                        return DELAYED_SAME
                    end
                end
            else
                return set_error('invalid date or day "' .. (tail or '') .. '"')
            end
        end
    end

-- Verify or wait for the specified time.
cmd_table['time'] =
    function(tail)
        -- Parse the tail as a time: 8:55 or 8:55 AM; 20:55 or 8:55 PM
        local ix, iy, hour, minute = tail:find('(%d+):(%d+)')
        if hour and minute then
            local show_want = tail:sub(ix,iy)

            local am_pm = tail:match('%s*(%a+)', iy+1)
            if am_pm then
                show_want = show_want .. ' ' .. am_pm
                am_pm = string.upper(am_pm)
                if (am_pm == 'AM') and (1*hour == 12) then
                    -- 12 AM is hour 0
                    hour = 0
                elseif (am_pm == 'PM') and (1*hour < 12) then
                    -- 1 to 11 PM is 13 to 23. 12 PM is just 12
                    hour = hour + 12
                end
            end
            local want_num = hour*60 + minute

            local now = os.date('*t')
            local now_num = now.hour*60 + now.min
            if now_num < want_num then
                -- Before the time: wait for it
                show_text('  Waiting until ' .. show_want .. '. Now ' .. os.date('%I:%M:%S %p'), true)
                return DELAYED_SAME
            elseif now_num < want_num + time_late_limit_minutes then
                -- Within a plausible window of the desired time
                show_text('Time is on or after ' .. show_want)
                return IMMEDIATE_NEXT
            else
                show_text('More than ' .. time_late_limit_minutes .. ' after the specified time ' .. show_want)
                return goto_label(tail)
            end
        else
            return set_error('invalid time "' .. (tail or '') .. '"')
        end
    end

-- Wait a specified number of seconds
cmd_table['wait'] =
    function(tail)
        local sec = tail:match('(%d+)')
        if sec == nil then
            return set_error('invalid wait time "' .. (tail or '') .. '"')
        end

        local delta = os.time() - time_command_started
        if delta < 1*sec then
            show_text('Waiting ' .. sec .. ' seconds: ' .. delta, true)
            return DELAYED_SAME
        end
        
        show_text('Waited ' .. tail .. ' seconds')
        return IMMEDIATE_NEXT
    end

-- Stop interpreting commands
cmd_table['stop'] =
    function(tail)
        set_state(STATE_STOP)
        show_text('STOPPED by command')
        return DELAYED_SAME
    end

-- Start streaming
cmd_table['start_streaming'] =
    function(tail)
        if obs.obs_frontend_streaming_active() then
            show_text('  Already streaming')
        else
            obs.obs_frontend_streaming_start()
            show_text('Started streaming')
        end
        return DELAYED_NEXT
    end

-- Stop streaming
cmd_table['stop_streaming'] =
    function(tail)
        if obs.obs_frontend_streaming_active() then
            obs.obs_frontend_streaming_stop()
            show_text('Stopped streaming')
        else
            show_text('  Not streaming')
        end

        return DELAYED_NEXT
    end

-- Start recording
cmd_table['start_recording'] =
    function(tail)
        if obs.obs_frontend_recording_active() then
            show_text('  Already recording')
        else
            obs.obs_frontend_recording_start()
            show_text('Started recording')
        end
        return DELAYED_NEXT
    end

-- Stop recording
cmd_table['stop_recording'] =
    function(tail)
        if obs.obs_frontend_recording_active() then
            obs.obs_frontend_recording_stop()
            show_text('Stopped recording')
        else
            show_text('  Not recording')
        end

        return DELAYED_NEXT
    end
