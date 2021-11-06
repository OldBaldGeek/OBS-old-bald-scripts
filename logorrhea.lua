-- logorrhea.lua
--
-- By John Hartman
--

obs = obslua

version = "0.1"

-- script_description returns the description shown to the user
function script_description()
    log_stuff("script_description")
    return '<h2>logorrhea.lua Version ' .. version ..'</h2>' ..
           [[<p>Logs OBS events etc. to help debug sequencing issues
           </p>
           ]]
end

-- script_load is called on startup
function script_load(settings)
    log_stuff("script_load")
    
    obs.obs_frontend_add_save_callback(on_save)
    obs.obs_frontend_add_event_callback(handle_frontend_event)

    local sh = obs.obs_get_signal_handler()
    obs.signal_handler_connect(sh, "source_activate", on_source_activate)
    obs.signal_handler_connect(sh, "source_deactivate", on_source_deactivate)
    obs.signal_handler_connect(sh, "source_show", on_source_show)
    obs.signal_handler_connect(sh, "source_hide", on_source_hide)
end

function script_unload()
    log_stuff("script_unload")
end

-- script_properties defines the properties that the user
-- can change for the entire script module itself
function script_properties()
    log_stuff("script_properties")
    
    local props = obs.obs_properties_create()
    obs.obs_properties_add_button(props, "enumerate_button", " ENUMERATE ", enumerate_button_clicked)
    return props
end

-- script_update is called when script settings are changed
function script_update(settings)
    log_stuff("script_update")
end

-- script_defaults is called to set the default settings
function script_defaults(settings)
    log_stuff("script_defaults")
end

-- script_save is called when the script is saved
function script_save(settings)
    log_stuff("script_save")
end

function on_save(save_data, saving, private_data)
    log_stuff( "on_save(" .. (saving and "saving)" or "loading)"))
end

event_strings = {}
event_strings[obs.OBS_FRONTEND_EVENT_STREAMING_STARTING] = "OBS_FRONTEND_EVENT_STREAMING_STARTING"
event_strings[obs.OBS_FRONTEND_EVENT_STREAMING_STARTED]  = "OBS_FRONTEND_EVENT_STREAMING_STARTED"
event_strings[obs.OBS_FRONTEND_EVENT_STREAMING_STOPPING] = "OBS_FRONTEND_EVENT_STREAMING_STOPPING"
event_strings[obs.OBS_FRONTEND_EVENT_STREAMING_STOPPED]  = "OBS_FRONTEND_EVENT_STREAMING_STOPPED"
event_strings[obs.OBS_FRONTEND_EVENT_RECORDING_STARTING] = "OBS_FRONTEND_EVENT_RECORDING_STARTING"
event_strings[obs.OBS_FRONTEND_EVENT_RECORDING_STARTED]  = "OBS_FRONTEND_EVENT_RECORDING_STARTED"
event_strings[obs.OBS_FRONTEND_EVENT_RECORDING_STOPPING] = "OBS_FRONTEND_EVENT_RECORDING_STOPPING"
event_strings[obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED]  = "OBS_FRONTEND_EVENT_RECORDING_STOPPED"
event_strings[obs.OBS_FRONTEND_EVENT_SCENE_CHANGED]      = "OBS_FRONTEND_EVENT_SCENE_CHANGED"
event_strings[obs.OBS_FRONTEND_EVENT_SCENE_LIST_CHANGED] = "OBS_FRONTEND_EVENT_SCENE_LIST_CHANGED"
event_strings[obs.OBS_FRONTEND_EVENT_TRANSITION_CHANGED] = "OBS_FRONTEND_EVENT_TRANSITION_CHANGED"
event_strings[obs.OBS_FRONTEND_EVENT_TRANSITION_STOPPED] = "OBS_FRONTEND_EVENT_TRANSITION_STOPPED"
event_strings[obs.OBS_FRONTEND_EVENT_TRANSITION_LIST_CHANGED]  = "OBS_FRONTEND_EVENT_TRANSITION_LIST_CHANGED"
event_strings[obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED] = "OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED"
event_strings[obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_LIST_CHANGED] = "OBS_FRONTEND_EVENT_SCENE_COLLECTION_LIST_CHANGED"
event_strings[obs.OBS_FRONTEND_EVENT_PROFILE_CHANGED]      = "OBS_FRONTEND_EVENT_PROFILE_CHANGED"
event_strings[obs.OBS_FRONTEND_EVENT_PROFILE_LIST_CHANGED] = "OBS_FRONTEND_EVENT_PROFILE_LIST_CHANGED"
event_strings[obs.OBS_FRONTEND_EVENT_EXIT]                 = "OBS_FRONTEND_EVENT_EXIT"
event_strings[obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_STARTING] = "OBS_FRONTEND_EVENT_REPLAY_BUFFER_STARTING"
event_strings[obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_STARTED]  = "OBS_FRONTEND_EVENT_REPLAY_BUFFER_STARTED"
event_strings[obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_STOPPING] = "OBS_FRONTEND_EVENT_REPLAY_BUFFER_STOPPING"
event_strings[obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_STOPPED]  = "OBS_FRONTEND_EVENT_REPLAY_BUFFER_STOPPED"
event_strings[obs.OBS_FRONTEND_EVENT_STUDIO_MODE_ENABLED]    = "OBS_FRONTEND_EVENT_STUDIO_MODE_ENABLED"
event_strings[obs.OBS_FRONTEND_EVENT_STUDIO_MODE_DISABLED]   = "OBS_FRONTEND_EVENT_STUDIO_MODE_DISABLED"
event_strings[obs.OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED]  = "OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED"
event_strings[obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CLEANUP] = "OBS_FRONTEND_EVENT_SCENE_COLLECTION_CLEANUP"
event_strings[obs.OBS_FRONTEND_EVENT_FINISHED_LOADING]    = "OBS_FRONTEND_EVENT_FINISHED_LOADING"
event_strings[obs.OBS_FRONTEND_EVENT_RECORDING_PAUSED]    = "OBS_FRONTEND_EVENT_RECORDING_PAUSED"
event_strings[obs.OBS_FRONTEND_EVENT_RECORDING_UNPAUSED]  = "OBS_FRONTEND_EVENT_RECORDING_UNPAUSED"
event_strings[obs.OBS_FRONTEND_EVENT_TRANSITION_DURATION_CHANGED] = "OBS_FRONTEND_EVENT_TRANSITION_DURATION_CHANGED"
event_strings[obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_SAVED] = "OBS_FRONTEND_EVENT_REPLAY_BUFFER_SAVED"
event_strings[obs.OBS_FRONTEND_EVENT_VIRTUALCAM_STARTED]  = "OBS_FRONTEND_EVENT_VIRTUALCAM_STARTED"
event_strings[obs.OBS_FRONTEND_EVENT_VIRTUALCAM_STOPPED]  = "OBS_FRONTEND_EVENT_VIRTUALCAM_STOPPED"
event_strings[obs.OBS_FRONTEND_EVENT_TBAR_VALUE_CHANGED]  = "OBS_FRONTEND_EVENT_TBAR_VALUE_CHANGED"

function handle_frontend_event(event)
    if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
        local str = event_strings[event]
        local scenesource = obs.obs_frontend_get_current_scene()
        if scenesource ~= nil then
            str = str .. ' to "' .. obs.obs_source_get_name(scenesource) .. '"'
            obs.obs_source_release(scenesource)
        end
        log_stuff(str)
    elseif event == obs.OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED then
        local str = event_strings[event]
        local scenesource = obs.obs_frontend_get_current_preview_scene()
        if scenesource ~= nil then
            str = str .. ' to "' .. obs.obs_source_get_name(scenesource) .. '"'
            obs.obs_source_release(scenesource)
        end
        log_stuff(str)
    elseif event_strings[event] then
        log_stuff(event_strings[event])
    else
        log_stuff("Unknown Front end event: " .. event)
    end
end
function on_source_activate(cs)
    local source = obs.calldata_source(cs, "source")
    local name = obs.obs_source_get_name(source)
    print( 'sig source_activate for "' .. name .. '"' )
end

function on_source_deactivate(cs)
    local source = obs.calldata_source(cs, "source")
    local name = obs.obs_source_get_name(source)
    print( 'sig source_deactivate for "' .. name .. '"' )
end

function on_source_show(cs)
    local source = obs.calldata_source(cs, "source")
    local name = obs.obs_source_get_name(source)
    print( 'sig source_show for "' .. name .. '"' )
end

function on_source_hide(cs)
    local source = obs.calldata_source(cs, "source")
    local name = obs.obs_source_get_name(source)
    print( 'sig source_hide for "' .. name .. '"' )
end

n_scenes = 0
n_sources = 0
function log_stuff(a_label)

    -- TODO: hack for mutex testing
    local nsec = obs.obs_get_average_frame_time_ns()
    local source = obs.obs_get_source_by_name()
    obs.obs_source_release(source)

    -- for each source, track scenes that use it
    local source_list = {}

    local scenes_now = 0
    local scenes = obs.obs_frontend_get_scenes()
    if scenes ~= nil then
        scenes_now = #scenes
    end

    local sources_now = 0
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        sources_now = #sources
    end

    print(a_label .. ' with ' .. scenes_now .. ' scenes and '.. sources_now .. ' sources')

    if (n_scenes ~= scenes_now) or (n_sources ~= sources_now) then
        -- Number of sources or scenes changed: enumerate them
        n_scenes = scenes_now
        if scenes ~= nil then
            for _, scenesource in ipairs(scenes) do
                local scene_name = obs.obs_source_get_name(scenesource)
                local scene = obs.obs_scene_from_source(scenesource)
                local items = obs.obs_scene_enum_items(scene)
                print('  Scene "' .. scene_name .. '" with ' .. #items .. ' sources')

                for _, item in pairs(items) do
                    local item_source = obs.obs_sceneitem_get_source(item)
                    local item_name = obs.obs_source_get_name(item_source)
                    local sx = source_list[item_name]
                    if sx == nil then
                        source_list[item_name] = {scene_name}
                    else
                        table.insert(sx, scene_name)
                    end
                end
                obs.sceneitem_list_release(items)
            end
        end

        n_sources = sources_now
        if sources ~= nil then
            for _, source in ipairs(sources) do
                local name = obs.obs_source_get_name(source)
                local id = obs.obs_source_get_id(source)

                local sx = source_list[name]
                local used_in = 0
                if sx then
                    used_in = #sx
                end

                print('  Source "' .. name .. '" with type ' .. id .. ' used in ' .. used_in .. ' scenes')
            end
        end
    end

    if sources ~= nil then
        obs.source_list_release(sources)
    end
    if scenes ~= nil then
        obs.source_list_release(scenes)
    end
end
