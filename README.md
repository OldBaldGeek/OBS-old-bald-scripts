# OBS-old-bald-scripts
Lua scripts, PTZ camera control, browser docks etc. for OBS and Zoom

These scripts and browser docks were written to simplify streaming of church services or similar events. Except as noted, these are independent items which can be used spearately or together.

You are welcome to use them, but thewy are mostly here just for my revision control.

## AutoStream.lua (OBS script)
Simple automated live-stream or recording based on a command file. Intended to perform basic actions when no OBS operator is available.

Commands to wait for a date, time, or interval, change scenes, adjust audio levels, start and stop streaming or recording.

## AutoStream_example.txt
Sample command file for use with AutoStream.lua. Livestream Sunday at 9:00 AM

## SimpleSlides.lua (OBS script)
Show a directory of image files as a slide show under hotkey control. This avoids the memory limitations of the OBS Slide Show source.

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

Replacement for cabrini-dock, adding support for VISCA cameras.
Uses camera-controller.js
Gets camera data from camera-data.js

## cabrini-dock.html, .js, .css (OBS browser dock)
Browser dock for OBS containing PTZ controls for two Aver VC520+ cameras, and a preview of current and upcoming slides from SimpleSlides.lua.
Uses button images from the images directory
Uses ljsocket.lua
Gets camera data from camera-data.js

## camera-control.html, -page2.html, .css, .js (OBS browser dock)
Obsolete browser dock to do PTZ control for an Aver VC520+ camera,
Replaced by cabrini-dock or cabrini-dock2

## zoom-dock2.html
Modified version of cabrini-dock2.html to be used in a browser to control PTZ cameras for Zoom meetings.
Uses camera-controller.js
Gets camera data from camera-data.js

## garvey-dock2.html, .css, garvey-camera-data.js
Modified version of cabrini-dock2.html to be used in a browser to control a Vaddio HD-20 PTZ camera using mouse-driven "joysticks" for PTZ

## camera-controller.js
PTZ camera interface classes used by various browser docks.
Currently supports Aver VC520+ via PTZApp, and some serial VISCA cameras
including the VC520+ and Vaddio HD-20

## visca-server.py
Simple web server to provide an XMLHttpRequest interface to RS-232 VISCA.
Inerface used by camera-controller.js

## images directory
Button images used by some of the browser docks listed above

## ljsocket.lua
Used by Camera-buddy.lua
This file actually belongs to the obs-visca-control plugin found on the OBS website. It is a socket library used by Camera-buddy.lua to control PTZ cameras over IP. Included here as a convenience

## speed_survey.py
Uses the speedtest-cli package to do periodic internet speed tests.

We wrote this to find the cause of large changes in internet speed to our streaming computer. Eventually traced to interference from fluorescent up-lights on an Ethernhet-over-powerline link.

## logorrhea.lua
Does a bunch of logging of OBS events as a diagnostic aid.

Depending on your setup, this may cause OBS to crash or lock up due to mutex deadlock. Probably more useful as a collection of bits to paste into your own scripts during debugging.




