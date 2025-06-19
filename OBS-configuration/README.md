# OBS Configuration

This directory tree contains OBS configuration files that use the scripts in our parent directory.

In operation, these files will be placed in and under C:\Users\...\AppData\Roaming\obs-studio

## global.ini

OBS basic configuration. Specifies (among other things) the Theme, Profile, Scene Collention,
and browser docks.

## basic

### scenes

Currently only "1280_x_720_Cameras.json"
About a dozen scenes using two Aver cameras. Uses many of the scripts in our parent directory.
Using OBS will change this file as scenes are changed, etc. This copy is here for
documentation and disaster recovery.

### profiles

This repo contains only SUNDAY, with basic.ini and service.json
- service.json contains streaming credentials. The key has been redacted
- Our live configuration also has profiles SPECIAL, AUTOMATIC, THURSDAY, FRIDAY,
  SATURDAY, and TEST; each specifying their own name and key. To make a full set
  - copy basic.ini and service.json into and appropriately named directory
  - edit basic.ini: in General/Name, replace "SUNDAY" with the new profile name
  - edit service.json to contain the matching streaming key
  - Create Windows shortcuts to run OBS using each profile. Something like
    
    **"C:\Program Files\obs-studio\bin\64bit\obs64.exe" --profile "SUNDAY"**

## themes

Contains JohnD.qss, a customization of the stock "Dark" theme. The only changes
are to widen and recolor the audio faders and their knobs.

This theme uses the stock "Dark" image files. If OBS can't find these files when
you select the "JohnD" theme, you may need to copy the approriate directory
from C:\Program Files\obs-studio\data\obs-studio\themes\Dark into AppData.

