# OBS-old-bald-scripts
Lua scripts, PTZ camera control, browser docks etc. for OBS and Zoom

These scripts and browser docks were written to simplify streaming of church services or similar events. Except as noted, these are independent items which can be used spearately or together, or ransacked for useful bits.

You are welcome to use them, but they are mostly here just for my revision control.

## OBS-configuration
Directory tree with OBS configuration files (AppData). Includes scene collection, profile, and theme.
Here for documentation and disaster recovery.

## AutoStream.lua (OBS script)
Simple automated live-stream or recording based on a command file. Intended to perform basic actions when no OBS operator is available.

Commands to wait for a date, time, or interval, change scenes, adjust audio levels, start and stop streaming or recording.

## AutoStream_example.txt
Sample command file for use with AutoStream.lua. "Livestream Sunday 9:00 AM"

## SimpleSlides.lua (OBS script)
Show a directory of image files as a slide show under hotkey control. This avoids the memory limitations of the OBS Slide Show source.

The images are typically exported from a PowerPoint deck.

## CamToggle.lua (OBS script)
Originally written to show or hide a music slide (see SimpleSlides.lua) on a scene with a camera.
 - Scene typically has a video source filling the screen
 - When toggled, the video source is shrunk to a specified percentage and moved to the upper right corner, and a music slide is shown in the lower left, overlapping part of the video image.
 - The sources to be operated on, and the scaling, are editable.

## Camera-buddy.lua (OBS script)
Coordinates the operation of two Aver PTZ video cameras. Sends PTZ preset commands when a scene is Previewed, unless that camera is in use on the Program, in which case the PTZ commands are deferred until the scene is transitioned to Program, and a message banner is shown in Preview. Could be modified to work with other cameras.

## camera-data.js
Data file with camera and preset information. Shared by Camera-buddy.lua and browser docks.


## cabrini-dock2.html, .js, .css (OBS browser dock)
Browser dock for OBS containing PTZ controls for two Aver VC520+ cameras, and a preview of current and upcoming slides from SimpleSlides.lua.

Replacement for cabrini-dock, adding support for VISCA cameras. Uses camera-controller.js. Gets camera data from camera-data.js

## cabrini-dock.html, .js, .css (OBS browser dock)
Browser dock for OBS containing PTZ controls for two Aver VC520+ cameras, and a preview of current and upcoming slides from SimpleSlides.lua.
Uses button images from the images directory. Uses ljsocket.lua. Gets camera data from camera-data.js
Replaced by cabrini-dock2.html.

## camera-control.html, -page2.html, .css, .js (OBS browser dock)
Obsolete browser dock to do PTZ control for an Aver VC520+ camera.
Replaced by cabrini-dock or cabrini-dock2

## zoom-dock2.html
Modified version of cabrini-dock2.html to be used in a browser to control PTZ cameras for Zoom meetings.

Uses camera-controller.js.  Gets camera data from camera-data.js

## garvey-dock2.html, .css, garvey-camera-data.js
Modified version of cabrini-dock2.html to be used in a browser to control a Vaddio HD-20 PTZ camera using mouse-driven "joysticks" for PTZ

## camera-controller.js
PTZ camera interface classes used by various browser docks.

Currently supports Aver VC520+ via PTZApp, and some serial VISCA cameras including the VC520+ and Vaddio HD-20

## visca-server.py
Simple web server to provide an XMLHttpRequest interface to RS-232 VISCA. Interface used by camera-controller.js

## SlideNumber.py
Given a set of files with names like "slide1, slide2, ... slide10, slide11", an alphabetical sort will give "slide1, slide10, slide11, slide2"
This script normalizes the numeric tails on the filenames with leading zeros so that alphabetical sort follows numerical order.

## ReaperMarker.lua
When recording, allows hotkeys to generate timestamps for import later as markers when editing the recorded audio in Reaper.

We record small presentations where the audience asks questions. The presider
has a microphone, and there is a room microphone to capture audience questions.
Rather than riding the room mic level during the recording, we record the
mics on separate channels, and post-process the audio in Reaper, cleaning up
the room audio when questions are being asked, and muting it otherwise.

Searching for questions in an hour-long presentation is very tedious, so this
script was added to let the OBS operator use hotkeys to flag when room or
presenter mic should be emphasized. The script generates a CSV file of Markers
which can be imported by Reaper via "View", "Region/Marker Manager", "Import..."

Given reaction times and occassional script delays, the markers will usually not
exactly match the desired edit point, but get you within a second or two of
the appropriate location.

## images directory
Button images used by some of the browser docks listed above

## ljsocket.lua
Used by Camera-buddy.lua. This file actually belongs to the obs-visca-control plugin found on the OBS website. It is a socket library used by Camera-buddy.lua to control PTZ cameras over IP. Included here as a convenience.

## speed_survey.py
Uses the speedtest-cli package to do periodic internet speed tests.

We wrote this to find the cause of large changes in internet speed to our streaming computer. Eventually traced to interference from fluorescent up-lights on an Ethernet-over-powerline link.

## logorrhea.lua
Does a bunch of logging of OBS events as a diagnostic aid.

Depending on your setup, this may cause OBS to crash or lock up due to mutex deadlock. Probably most useful as a collection of bits to paste into your own scripts during debugging.
