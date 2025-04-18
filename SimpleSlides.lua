-- SimpleSlides.lua
--
-- By John Hartman
--
-- Thanks to tid-kijyun, whose tally-counter.lua I used as a framework.
-- https://gist.github.com/tid-kijyun/477c723ea42d22903ebe6b6cee3f77a1
--

--[[
This scrip was written display PowerPoint slides exported as png images,
allowing an operator to show them in a stream without needing to switch back
and forth between OBS and PowerPoint.

When this script was created, the OBS Image Slide Show source loaded all images
into video memory. That let it change slides without rendering lags, but limited
the size of the slideshow, as video memory is a limited resource. This
restriction has been relaxed/removed in later versions of OBS, but this script
has other features.

This script avoids any memory limitations by simply loading a new image file into
an Image Source for each slide. The trade off is that a few frames may be
dropped during changes of large images due to rendering lag.
On my PC with an i7 4770 and Intel HD4600 graphics, it drops the same number of
frames as are dropped if you manually change the filespec for an Image Source:
no drops for 1280x720 images, up to 4 frames dropped for 3306x1860 images.
If a scene contains only the slide, drops are hard to see. 
If a scene also has a camera or other moving source, it can be noticeable.
--]]

obs = obslua

local version = "2.0"

-- Set true to get debug printing
local debug_print_enabled = false

-- The name of our controlling Sources must begin with this string
local source_key = 'SimpleSlides:'

-- We accept files with the following extensions (acceptable to the Image Source)
local allowed_filetypes = {
    ["png"] = true,
    ["jpg"] = true,
    ["jpeg"] = true,
    ["bmp"] = true,
    ["gif"] = true,
}

-- A table of slide show data, indexed by Source name.
-- Each entry contains a sorted list of filenames, and the index of the current slide.
local slide_shows = {}

-- The currently active slideshow: hotkeys and buttons apply to this one
local active_source_name  = ""

local hotkey_reset_id    = obs.OBS_INVALID_HOTKEY_ID
local hotkey_next_id     = obs.OBS_INVALID_HOTKEY_ID
local hotkey_previous_id = obs.OBS_INVALID_HOTKEY_ID

-- script_description returns the description shown to the user
function script_description()
    debug_print("in script_description")
    return '<h2>SimpleSlides Version ' .. version ..'</h2>' ..
           [[<p>Use an Image Source whose name begins with "SimpleSlides:" to
            display sequential image files from a directory, creating a simple
            slide show without the memory limitations of the OBS Image Slide
            Show. However, some frames may be dropped during image changes.</p>
            
            <p>The filespec in the Image Source is used to specify the directory.
            Files of type png, jpg, jpeg, bmp, and gif will be shown.
            Filenames that end in digits are ordered numerically. Thus
            Slide1.png, Slide2.png, Slide10.png will be shown in the correct
            order, rather than Slide1.png, Slide10.png, Slide2.png as
            Windows alphabetic sort would show them.
            </p>

            <p>Slides may be changed via assignable hotkey, or via the buttons
            below. Hotkeys and buttons act only if a SimpleSlide Image Source
            is visible in the Preview or Program window.</p>
            
            <p>You can have multiple independent slide shows using Sources with
            unique names: for example "SimpleSlides: lyrics" and
            "SimpleSlides: sermon graphics". Hotkeys and buttons will act on
            whichever slideshow is visible in the Preview or Program window,
            with Program taking precedence.</p>
           ]]
end

----------------------------------------------------------
-- Log a message if debugging is enabled
function debug_print(a_string)
    if debug_print_enabled then
        print(a_string)
    end
end

----------------------------------------------------------
-- script_properties defines the properties that the user
-- can change for the entire script module itself
function script_properties()
    debug_print("in script_properties")
    
    local props = obs.obs_properties_create()
    
    -- Drop-list of SimpleSlides Image Sources
    local p = obs.obs_properties_add_list(props, "source", "Slide Show", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            if obs.obs_source_get_id(source) == "image_source" then
                local name = obs.obs_source_get_name(source)
                ix,len = string.find(name, source_key)
                if ix == 1 then
                    debug_print( 'script_properties adding source "' .. name .. '"')
                    obs.obs_property_list_add_string(p, name, name)
                end
            end
        end
    end
    obs.source_list_release(sources)
    obs.obs_property_set_modified_callback(p, prop_slideshow_changed)
    
    -- Directory for the source
    p = obs.obs_properties_add_path(props, "directory", "Directory", obs.OBS_PATH_DIRECTORY, nil, nil)
    obs.obs_property_set_modified_callback(p, prop_directory_changed)

    -- Current slide number
    p = obs.obs_properties_add_int(props, "slide_number", "Current Slide", 0, 100000, 1)

    obs.obs_properties_add_button(props, "next_button",     " NEXT ", next_button_clicked)
    obs.obs_properties_add_button(props, "previous_button", " PREV ", previous_button_clicked)
    obs.obs_properties_add_button(props, "reset_button",    "RESET",  reset_button_clicked)

    return props
end

-- UI: change to selected slideshow
function prop_slideshow_changed(props, property, settings)
    local show_name = obs.obs_data_get_string(settings, "source")
    local show_directory = obs.obs_data_get_string(settings, "directory")
    local slide_number = obs.obs_data_get_int(settings, "slide_number")
    print( 'prop_slideshow_changed for "' .. show_name .. '" directory "' .. show_directory .. '" slide ' .. slide_number)

    -- Get path and slide number for this show and update the controls
    local current_slide = 1
    local path = ''
    local show = slide_shows[show_name]
    if not show then
        print('No slideshow data for "' .. show_name .. '"')
    else
        current_slide = show['current_slide']
        filenames     = show['filenames']
        local name, extention
        path, name, extension = splitpath(filenames[1])
    end

    print('Slideshow "' .. show_name .. '" with path "' .. path .. ' on slide ' .. current_slide)
    obs.obs_data_set_int(settings, "slide_number", current_slide)
    obs.obs_data_set_string(settings, "directory", path)

    return true
end

-- UI: change to selected directory
function prop_directory_changed(props, property, settings)
    local show_name = obs.obs_data_get_string(settings, "source")
    local show_directory = obs.obs_data_get_string(settings, "directory")
    local slide_number = obs.obs_data_get_int(settings, "slide_number")
    print( 'prop_directory_changed for "' .. show_name .. '" directory "' .. show_directory .. '" slide ' .. slide_number)

    -- Update the SLIDESHOW
    local show = slide_shows[show_name]
    if not show then
        print('prop_directory_changed : No slideshow data for "' .. show_name .. '"')
    else
        -- TODO: replace show['filenames'], and perhaps reset slide to 1
        print('prop_directory_changed: change directory for "' .. show_name .. '" to "' .. show_directory .. '"')
    end

    return true
end

-- script_update is called when script settings are changed
function script_update(settings)
    debug_print('in script_update')
end

-- script_defaults is called to set the default settings
function script_defaults(settings)
    debug_print("in script_defaults")
end

-- script_save is called when the script is saved
-- We save our hotkey assignments
function script_save(settings)
    debug_print("in script_save")

    local save_array = obs.obs_hotkey_save(hotkey_reset_id)
    obs.obs_data_set_array(settings, "reset_hotkey", save_array)
    obs.obs_data_array_release(save_array)

    save_array = obs.obs_hotkey_save(hotkey_next_id)
    obs.obs_data_set_array(settings, "next_slide_hotkey", save_array)
    obs.obs_data_array_release(save_array)
    
    save_array = obs.obs_hotkey_save(hotkey_previous_id)
    obs.obs_data_set_array(settings, "previous_slide_hotkey", save_array)
    obs.obs_data_array_release(save_array)
end

-- script_load is called on startup
function script_load(settings)
    print("SimpleSlides version " .. version)

    obs.obs_frontend_add_save_callback(on_save)
    obs.obs_frontend_add_event_callback(handle_frontend_event)

    -- Connect our hotkeys
    hotkey_reset_id = obs.obs_hotkey_register_frontend("simpleslides_reset_button", "[SimpleSlides]Reset", reset)
    hotkey_next_id  = obs.obs_hotkey_register_frontend("simpleslides_next_button", "[SimpleSlides]Next", next_slide)
    hotkey_previous_id = obs.obs_hotkey_register_frontend("simpleslides_previous_button", "[SimpleSlides]Previous", previous_slide)

    local save_array = obs.obs_data_get_array(settings, "reset_hotkey")
    obs.obs_hotkey_load(hotkey_reset_id, save_array)
    obs.obs_data_array_release(save_array)

    save_array = obs.obs_data_get_array(settings, "next_slide_hotkey")
    obs.obs_hotkey_load(hotkey_next_id, save_array)
    obs.obs_data_array_release(save_array)
    
    save_array = obs.obs_data_get_array(settings, "previous_slide_hotkey")
    obs.obs_hotkey_load(hotkey_previous_id, save_array)
    obs.obs_data_array_release(save_array)
    
    -- See if a slideshow is active
    -- (when the script is reloaded - during startup, no scenes loaded yet)
    select_slideshow("script_load")
end

function script_unload()
    debug_print("SimpleSlides script_unload")
end

-- on_save(loading) is called at startup and when a scene collection is loaded.
-- on_save(saving) is called when anything in a scene_collection is changed, 
-- just before a new scene collection is loaded, and during showdown.
function on_save(save_data, saving, private_data)
	debug_print( "on_save(" .. (saving and "saving)" or "loading)"))
	if not saving then
        -- TODO: loading a new scene-set should wipe all slideshow data.
        select_slideshow("on_save(load)")
    else
        -- TODO: a change to one of our sources should reset its slideshow data
        -- But on_save is called for ANY save, of anything.
        select_slideshow("on_save(save)")
	end
end

function handle_frontend_event(event)
	if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
        -- get a preview event before this anyway, so avoid duplicate action
        debug_print("OBS_FRONTEND_EVENT_SCENE_CHANGED")
    elseif event == obs.OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED then
        select_slideshow("OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED")
	elseif event == obs.OBS_FRONTEND_EVENT_EXIT then
	   debug_print("OBS_FRONTEND_EVENT_EXIT")
	elseif event == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING then
	   debug_print("OBS_FRONTEND_EVENT_FINISHED_LOADING")
    end
end

-- Given a path, return the directory part (including final slash or backslash)
-- file part, extension part (not including dot)
-- if there's no directory part, or extension, some strings may be empty
-- Yes, I know you could do it in one line using regex.
function splitpath(filespec)
    local path, name, extension

    local i = #filespec
    while i > 0 do
        local ch = string.sub(filespec,i,i)
        if ch == '\\' or ch == '/' then break end
        i = i - 1
    end

    if i == 0 then
        path = ''
    else
        path = string.sub(filespec,1,i)
    end

    local j = #filespec
    while j > i+1 do
        local ch = string.sub(filespec,j,j)
        if ch == '.' then break end
        j = j - 1
    end

    if j == i+1 then
        name = string.sub(filespec,i+1)
        extension = ''
    else
        name = string.sub(filespec,i+1,j-1)
        extension = string.sub(filespec,j+1)
    end
    
    return path, name, extension
end

-- Return the filename in lower case, and any trailing digits as an integer
-- If there are no trailing digits, the numeric value returns -1
function name_and_number(file_name)
    local fname, fnumber = string.match( string.lower(file_name), "(.-)(%d*)%.")
    if fnumber == nil or fnumber == '' then
        fnumber = '-1'
    end

    return fname, tonumber(fnumber)
end

-- If we don't have slideshow data for special_image_name, create it now
function create_slideshow_if_needed(special_image_name)
    if slide_shows[special_image_name] then
        debug_print('Slideshow exists for "' .. special_image_name .. '"')
    else
        debug_print('Creating slideshow for "' .. special_image_name .. '"')

        local show = {}
        
        local source = obs.obs_get_source_by_name(special_image_name)
        if source == nil then 
            print('ERROR: no source for "' .. special_image_name .. '"')
        else
            -- Filespec is as entered when the source was created, possibly
            -- changed if the scene was saved after we advanced to another slide.
            -- We extract the parts we need (currently just the path)
            local settings = obs.obs_source_get_settings(source)
            if not settings then
                print('ERROR: no settings for "' .. special_image_name .. '"')
            else
                local filespec = obs.obs_data_get_string(settings, 'file')
                obs.obs_data_release(settings)
                
                local path, name, extension
                path, name, extension = splitpath(filespec)
                debug_print('Filespec="' .. filespec .. '" path="' .. path .. '" name="' .. name .. '" ext="' .. extension .. '"')

                local filenames = {}
                local dir = obslua.os_opendir(path)
                local entry
                repeat
                    entry = obslua.os_readdir(dir)
                    if entry and not entry.directory then
                        local xpath
                        xpath, name, extension = splitpath(entry.d_name)
                        if allowed_filetypes[string.lower(extension)] then
                            -- debug_print('  Image file="' .. entry.d_name .. '"')
                            table.insert(filenames, path .. entry.d_name)
                        end
                    end
                until not entry
                obslua.os_closedir(dir)
                
                -- Order the names: alphabetical, but trailing numerals in order
                table.sort(filenames,
                    function(a,b)
                        local a_name, a_number = name_and_number(a)
                        local b_name, b_number = name_and_number(b)
                        if a_name ~= b_name then
                            return a_name < b_name
                        end
                        return a_number < b_number
                    end )

                -- Save the slideshow for later use
                show['filenames'] = filenames
                show['current_slide'] = 1
                slide_shows[special_image_name] = show

                do_slide('from create_slideshow_if_needed', 'SHOW_SLIDE')
            end
            obs.obs_source_release(source)
        end
    end
end

-- If the scene has a source_key source, return its name; else ""
function get_key_source(label, scenesource)
    retval = ''

    if scenesource ~= nil then
        local scene_name = obs.obs_source_get_name(scenesource)
        debug_print(label .. ' get_key_source for "' .. scene_name .. '"')

        local scene = obs.obs_scene_from_source(scenesource)
        local items = obs.obs_scene_enum_items(scene)
        for i, item in pairs(items) do
            local item_source = obs.obs_sceneitem_get_source(item)
            local item_name = obs.obs_source_get_name(item_source)
            -- debug_print( '  ' .. label .. ' "' .. scene_name .. '" source "' .. item_name .. '"')
            if obs.obs_source_get_id(item_source) == "image_source" then
                ix,len = string.find(item_name, source_key)
                if ix == 1 then
                    debug_print( '  ' .. label .. ' "' .. scene_name .. '" has "' .. item_name .. '"')
                    retval = item_name
                    break
                end
            end
        end
        obs.sceneitem_list_release(items)
    end

    return retval
end

-- Select a slide show.
-- Called after save or load, and for OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED,
-- which is also called on scene activation
function select_slideshow(label)
    debug_print('select_slideshow ' .. label)

    -- no show active unless we find one
    local desired_source_name = ''

    local scenesource = obs.obs_frontend_get_current_scene()
    desired_source_name = get_key_source("Program", scenesource)
    obs.obs_source_release(scenesource)

    if desired_source_name == '' then
        -- Program has no slideshow, see if Preview does
        scenesource = obs.obs_frontend_get_current_preview_scene()
        desired_source_name = get_key_source("Preview", scenesource)
        obs.obs_source_release(scenesource)
    end

    if desired_source_name ~= '' then
        create_slideshow_if_needed(desired_source_name)
    end

    if active_source_name ~= desired_source_name then
        active_source_name = desired_source_name
        do_slide(label, 'SHOW_SLIDE')
    end
end

function do_slide(label, action)
    debug_print('do_slide ' .. label .. ' action ' .. action)

    if active_source_name ~= '' then
        show = slide_shows[active_source_name]
        if not show then
            print('ERROR: no slideshow exists for "' .. active_source_name .. '"')
        else
            local source = obs.obs_get_source_by_name(active_source_name)
            if source then
                local current_slide = show['current_slide']
                local filenames     = show['filenames']

                if action == 'SHOW_SLIDE' then
                    -- no change to slide index
                elseif action == 'NEXT_SLIDE' then
                    if current_slide < #filenames then
                        current_slide = current_slide + 1
                    end
                elseif action == 'PREV_SLIDE' then
                    if current_slide > 1 then
                        current_slide = current_slide - 1
                    end
                elseif action == 'FIRST_SLIDE' then
                    current_slide = 1
                else
                    print('ERROR: invalid action ' .. action .. ' requested for "' .. active_source_name .. '"')
                end

                show['current_slide'] = current_slide
                local new_filename = filenames[current_slide]
                local next_filename = ''
                if current_slide < #filenames then
                    next_filename = filenames[current_slide+1]
                end

                local current_filename = ''

                local nowSettings = obs.obs_source_get_settings(source)
                if not nowSettings then
                    print( "ERROR: Failed to get current settings for " .. active_source_name )
                else
                    current_filename = obs.obs_data_get_string(nowSettings, "file") 
                    obs.obs_data_release(nowSettings)
                    -- debug_print( "Old file for " .. active_source_name .. ' is ' .. current_filename)
                end
                
                if new_filename and (new_filename ~= current_filename) then
                    local settings = obs.obs_data_create()

                    -- Changing "file" causes the displayed image to update.
                    -- It may also be monitored by a Websocket client.
                    -- We stuff the next slide into "next_file" so the
                    -- Websocket can see that as well
                    obs.obs_data_set_string(settings, "file", new_filename)
                    obs.obs_data_set_string(settings, "next_file", next_filename)
                    obs.obs_source_update(source, settings)
                    obs.obs_data_release(settings)

                    print( "File[" .. current_slide .. "] for " .. active_source_name .. ' is ' .. new_filename)
                end

                obs.obs_source_release(source)
            end
        end
    end
end

function reset_button_clicked(props, p)
    reset(true)
    return false
end

function next_button_clicked(props, p)
    next_slide(true)
    return false
end

function previous_button_clicked(props, p)
    previous_slide(true)
    return false
end

function reset(pressed)
    if pressed and (active_source_name ~= '') then
        -- Delete the current slideshow, to force a refresh of the file list
        debug_print("Deleting slideshow for " .. active_source_name)
        slide_shows[active_source_name] = nil
        create_slideshow_if_needed(active_source_name)
    end
end

function next_slide(pressed)
    if pressed then
        do_slide('next_slide', 'NEXT_SLIDE')
    end
end

function previous_slide(pressed)
    if pressed then
        do_slide('prev_slide', 'PREV_SLIDE')
    end
end
