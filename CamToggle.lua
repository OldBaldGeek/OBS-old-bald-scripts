local obs = obslua
local version = "0.4"

-- Set true to get debug printing
local debug_print_enabled = false

-- Global variables to restore the scene
local stretchable_source_id = "dshow_input"  -- ID of the source to act on
local hideable_source_name  = ""             -- Name of the source to hide
local stretch_factor        = 66             -- percent of fullscreen

-- Identifier of the hotkey set by OBS
local hotkey_toggle_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_clean_id  = obs.OBS_INVALID_HOTKEY_ID

-- Description displayed in the Scripts dialog window
function script_description()
    return '<h2>CamToggle Version ' .. version ..'</h2>' ..
           [[<p>Toggle a camera between split screen and full screen,
           hiding a specified Source, such as a slide show.</p>]]
end

-- Log a message if debugging is enabled
function debug_print(a_string)
    if debug_print_enabled then
        print(a_string)
    end
end

-- Called at script load
function script_load(settings)
    print("CamToggle version " .. version)

    -- Connect our callbacks
    hotkey_toggle_id = obs.obs_hotkey_register_frontend("camtoggle_button", "[CamToggle]toggle", on_hotkey)
    local hotkey_save_array = obs.obs_data_get_array(settings, "toggle_hotkey")
    obs.obs_hotkey_load(hotkey_toggle_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_clean_id  = obs.obs_hotkey_register_frontend("camtoggle_clean_button", "[CamToggle]clean", on_clean_hotkey)
    hotkey_save_array = obs.obs_data_get_array(settings, "clean_hotkey")
    obs.obs_hotkey_load(hotkey_clean_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

-- Called at script unload
function script_unload()
end

-- Called to set default values of data settings
function script_defaults(settings)
  obs.obs_data_set_default_string(settings, "stretchable_source_id", "")
  obs.obs_data_set_default_string(settings, "hideable_source_name", "")
  obs.obs_data_set_default_double(settings, "stretch_factor", stretch_factor)
end

-- Called to display the properties GUI
function script_properties()
    props = obs.obs_properties_create()

    -- Drop-down list of resizeable sources
    local desig_property = obs.obs_properties_add_list(props, "stretchable_source_id",
            "Type of source to toggle between full and split screen",
            obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    populate_list_with_stretchable_source_ids(desig_property)

    -- Drop-down list of hideable sources
    local hide_property = obs.obs_properties_add_list(props, "hideable_source_name",
            "Name of source to hide/show",
            obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    populate_list_with_source_names(hide_property)

    local stretch_property = obs.obs_properties_add_int(props, "stretch_factor",
            "Split as Percentage of fullscreen", 10, 100, 1)

    -- Button to refresh the drop-down lists
    obs.obs_properties_add_button(props, "button", "Refresh type and source lists",
        function() 
            populate_list_with_stretchable_source_ids(desig_property) 
            populate_list_with_source_names(hide_property) 
            return true 
        end)

    return props
end

-- Called after change of settings including once after script load
function script_update(settings)
    stretchable_source_id = obs.obs_data_get_string(settings, "stretchable_source_id")
    hideable_source_name = obs.obs_data_get_string(settings, "hideable_source_name")
    stretch_factor = obs.obs_data_get_int(settings, "stretch_factor")
end

-- Called before data settings are saved
function script_save(settings)
    -- Hotkey save
    local hotkey_save_array = obs.obs_hotkey_save(hotkey_toggle_id)
    obs.obs_data_set_array(settings, "toggle_hotkey", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_hotkey_save(hotkey_clean_id)
    obs.obs_data_set_array(settings, "clean_hotkey", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

-- Fill the given list property object with the type IDs of all sources plus an empty one
function populate_list_with_stretchable_source_ids(list_property)
    obs.obs_property_list_clear(list_property)
    obs.obs_property_list_add_string(list_property, "", "")

    -- We would like to call obs_enum_source_types, but as of Sept 18, 2021
    -- and OBS issue 3462, its Lua interface is broken, since the C function
    -- takes **array as an arg.
    -- So we grab the types of the current sources, eliminate duplicates,
    -- and live without any types we don't yet have an instance of.
    local sources = obs.obs_enum_sources()

    -- Use a table to ignore redundant types
    local types = {}
    for _,source in pairs(sources) do
        local typee = obs.obs_source_get_unversioned_id(source)
        types[typee] = typee
    end

    -- Sort the types
    local arr = {}
    for typee in pairs(types) do
        table.insert(arr, typee)
    end
    table.sort(arr)
    for i,typee in ipairs(arr) do
        debug_print( "Type='" .. typee .. "'")
        obs.obs_property_list_add_string(list_property, typee, typee)
    end    

    obs.source_list_release(sources)
end

-- Fill the given list property object with the names of all sources plus an empty one
function populate_list_with_source_names(list_property)
    obs.obs_property_list_clear(list_property)
    obs.obs_property_list_add_string(list_property, "", "")

    local sources = obs.obs_enum_sources()
    local names = {}
    for _,source in pairs(sources) do
        table.insert(names, obs.obs_source_get_name(source))
    end
    
    table.sort(names)
    for i,name in ipairs(names) do
        debug_print( "Source='" .. name .. "'")
        obs.obs_property_list_add_string(list_property, name, name)
    end
    obs.source_list_release(sources)
end

-- Search a_scene for a source with the specified typeID
-- Return the scene_item, else nil
function find_sceneitem_with_id(a_scene, a_id)
    local retval = nil
    local items = obs.obs_scene_enum_items(a_scene)
    for i, item in pairs(items) do
        local item_source = obs.obs_sceneitem_get_source(item)
        if obs.obs_source_get_unversioned_id(item_source) == a_id then
            retval = item
            break
        end
    end
    obs.sceneitem_list_release(items)
    return retval
end

function show_sizing(a_label, a_scene_source, a_width, a_height)
    local name = obs.obs_source_get_name(a_scene_source)
    debug_print(a_label .. " '" .. name .. "' (" .. a_width .. "," .. a_height .. ")")
end

-- Set stretchable source fullscreen, and hide hideable source.
function set_fullscreen(scene_source, stretchable_item, hideable_item)
    local vec = obs.vec2()
    obs.obs_sceneitem_defer_update_begin(stretchable_item)
    vec.x = obs.obs_source_get_width(scene_source)
    vec.y = obs.obs_source_get_height(scene_source)
    obs.obs_sceneitem_set_bounds(stretchable_item, vec)
    show_sizing("Set fullscreen", scene_source, vec.x, vec.y)
    vec.x = 0
    vec.y = 0
    obs.obs_sceneitem_set_pos(stretchable_item, vec)
    obs.obs_sceneitem_defer_update_end(stretchable_item)

    -- Hide the hideable
    obs.obs_sceneitem_set_visible(hideable_item, false)
end

-- Set stretchable source to part screen, and show hideable source.
function restore_scene(scene_source, stretchable_item, hideable_item)
    local vec = obs.vec2()
    scene_width = obs.obs_source_get_width(scene_source)
    scene_height = obs.obs_source_get_height(scene_source)

    obs.obs_sceneitem_defer_update_begin(stretchable_item)
    vec.x = (scene_width * stretch_factor) / 100
    vec.y = (scene_height * stretch_factor) / 100
    obs.obs_sceneitem_set_bounds(stretchable_item, vec)
    vec.x = scene_width - vec.x
    show_sizing("Set splitscreen", scene_source, vec.x, vec.y)
    vec.y = 0
    obs.obs_sceneitem_set_pos(stretchable_item, vec)
    obs.obs_sceneitem_defer_update_end(stretchable_item)

    -- Show the hideable
    obs.obs_sceneitem_set_visible(hideable_item, true)
end

-- Callback for the toggle hotkey
function on_hotkey(pressed)
    if pressed then
        local scene_source = obs.obs_frontend_get_current_preview_scene()
        if scene_source then
            -- We need both a stretchable item and a hideable item
            local current_scene = obs.obs_scene_from_source(scene_source)
            local stretchable_item = find_sceneitem_with_id(current_scene, stretchable_source_id)
            local hideable_item = obs.obs_scene_find_source_recursive(current_scene, hideable_source_name)
            if stretchable_item and hideable_item then
                if obs.obs_sceneitem_visible(hideable_item) then
                    -- visible source means NOT fullscreen: set fullscreen
                    set_fullscreen(scene_source, stretchable_item, hideable_item)
                else
                    -- restore from fullscreen
                    restore_scene(scene_source, stretchable_item, hideable_item)
                end
            end
            obs.obs_source_release(scene_source)
        end
    end
end

function on_clean_hotkey(pressed)
    if pressed then
        local scene_source = obs.obs_frontend_get_current_preview_scene()
        if scene_source then
            -- We need both a stretchable item and a hideable item
            local current_scene = obs.obs_scene_from_source(scene_source)
            local stretchable_item = find_sceneitem_with_id(current_scene, stretchable_source_id)
            local hideable_item = obs.obs_scene_find_source_recursive(current_scene, hideable_source_name)
            if stretchable_item and hideable_item then
                if obs.obs_sceneitem_visible(hideable_item) then
                    -- visible source means NOT fullscreen: set fullscreen
                    set_fullscreen(scene_source, stretchable_item, hideable_item)
                else
                    -- already fullscreen
                end
            end
            obs.obs_source_release(scene_source)
        end
    end
end

