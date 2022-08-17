# OBS-old-bald-scripts
Lua scripts, browser docks etc. for OBS

These scripts were written to simplify streaming of church services
or similar events.

AutoStream.lua
	Simple automated live-stream or recording based on a command file.
	Commands to wait for a date, time, or interval, change scenes,
	Adjust audio levels, start and stop streaming or recording.

AutoStream_example.txt
	Sample command file for use with AutoStream.lua

SimpleSlides.lua
	Show a directory of image files as a slide show under hotkey control.
	This avoids the memory limitations of the OBS Slide Show source.

CamToggle.lua
	Originally written to show or hide a music slide on a scene with a camera.
	- Scene typically has a video source filling the screen
	- When toggled, the video source is shrunk to a specified percentage and
	  moved to the upper right corner, and a music slide is shown in the lower
	  left, overlapping part of the video image.
	The sources to be operated on, and the scaling, are adjustable.

Camera-buddy.lua
	Coordinates the operation of two Aver PTZ video cameras.
	Sends PTZ preset commands when a scene is Previewed, unless that
	camera is in use on the Program, in which case the PTZ commands
	are deferred until the scene is transitioned to Program, and
	a message banner is shown in Preview.
	Could be modified to work with other cameras.

camera-data.js
	Data file with camera and preset information. Shared by Camera-buddy.lua
	and browser docks.

ljsocket.lua
	This file actually belongs to the obs-visca-control plugin found on
	the OBS website. It is a socket library used by Camera-buddy.lua to
	control PTZ cameras over IP. Included here as a convenience
