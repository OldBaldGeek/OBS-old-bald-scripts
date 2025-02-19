#!/usr/bin/python
# Convert between Reaper and Shotcut marker formats
#
# When using OBS to record for later editing, it is sometimes useful for
# the operator to flag where attention may be needed during editing, such as
# - Audio level changes (audience questions, presenter wanders off mic...)
# - Scene or camera changes
# - Change of PowerPoint or similar slides
#
# The Lua script MarkerMaker.lua may be used in OBS to collect operator flags
# into a CSV file during recording.
#
# The CSV file is in a format that can be loaded to set markers in Reaper for
# audio editing.
#
# Alternatively, this program can merge the markers from the .CSV file into a
# Shotcut .MLT file to assist in video or audio editing there.
#
# This program can also dump markers from .CSV and .MLT files,
# or remove markers from a .MLT file.

import os
import sys
import time
import xml.etree.ElementTree as ET
import csv

g_version = "1.3"

#==============================================================================
# Convert time in seconds.msec (from CSV) into HH:MM:SS.MSEC (for MLT)
# input is float, output is string
def seconds_as_hms(a_seconds):
    t = float(a_seconds)

    hours = int(t/3600)
    t = t - (hours*3600)
    minutes = int(t/60)
    t = t - (minutes*60)
    seconds = int(t)
    t = t - seconds
    msec = int(1000*t)
    return '%02u:%02u:%02u.%03u' % (hours, minutes, seconds, msec)


#==============================================================================
# Convert time in HH:MM:SS.MSEC (from MLT) to seconds.msec (for CSV)
# input is string, output is string
def hms_as_seconds(a_hms):
    parts = a_hms.split(':')
    seconds = 3600*int(parts[0]) + 60*int(parts[1]) + float(parts[2])
    return '%.3f' % (seconds)


#==============================================================================
# Dump any markers in a Shotcut .mlt file
# xml file. Marker section (if any) appears
#  <tractor id="tractor0" title="Shotcut version 23.12.15" in="00:00:00.000" out="01:21:59.520">
#    <properties name="shotcut:markers">
#      <properties name="0">
#        <property name="text">Marker 1</property>
#        <property name="start">00:01:18.760</property>      Shotcut shows this as 1:18:19
#        <property name="end">00:01:18.760</property>
#        <property name="color">#008000</property>
#      </properties>
#      ...
#    </properties>
#
def dump_mlt(infile_name):
    tree = ET.parse(infile_name)
    root = tree.getroot()

    markers = root.find('.//*[@name="shotcut:markers"]')
    if markers is None:
        print('File contains no markers')
    else:
        for marker in markers:
            marker_data = {}
            marker_data['number'] = marker.get('name')
            for item in marker.iter('property'):
                marker_data[item.get('name')] = item.text

            print( marker_data )

#==============================================================================
# Dump any markers in a Shotcut .mlt file to a Reaper-compatible .csv file
#
def dump_mlt_as_csv(infile_name, outfile_name):
    tree = ET.parse(infile_name)
    root = tree.getroot()

    markers = root.find('.//*[@name="shotcut:markers"]')
    if markers is None:
        print('File contains no markers')
    else:
        newname = outfile_name + '.tmp'
        with open(newname, 'w', newline='') as csvfile:
            writer = csv.writer(csvfile)
            writer.writerow(['#', 'Name', 'Start', 'End', 'Color'])

            for marker in markers:
                marker_index = marker.get('name')
                marker_data = {}
                for item in marker.iter('property'):
                    marker_data[item.get('name')] = item.text

                csv_row = [ '', '', '', '', '']
                csv_row[1] = marker_data['text']
                csv_row[2] = hms_as_seconds( marker_data['start'] )
                if marker_data['end'] == marker_data['start']:
                    # Marker omits end time
                    csv_row[0] = 'M' + marker_index
                else:
                    # Range with start and end times
                    csv_row[0] = 'R' + marker_index
                    csv_row[3] = hms_as_seconds( marker_data['end'] )

                csv_row[4] = marker_data['color'].strip('#')
                writer.writerow(csv_row)

        # Output the new CSV file, saving a backup of the original
        backup_file = outfile_name + '.bak'
        try:
            os.remove(backup_file)
        except FileNotFoundError:
            pass

        try:
            os.rename(outfile_name, backup_file)
        except FileNotFoundError:
            pass

        os.rename(newname, outfile_name)


#==============================================================================
# Merge the markers from CSV file infile_name into Shotcut MLT file outfile_name
# If infile_name is empty, then REMOVE all markers from outfile_name
#
# Timestamps are displayed in Shotcut as HH:MM:SS:FRAME
# but the XML nicely has HH:MM:SS:FRAME.MSEC
#
# - the properties name -> CSV "#"
# - text -> CSV Name
# - start -> CSV Start
# - end -> CSV End
# - color -> CSV Color
#
def update_mlt(infile_name, outfile_name, time_shift_sec):
    tree = ET.parse(outfile_name)
    root = tree.getroot()

    markers = root.find('.//*[@name="shotcut:markers"]')
    if markers is None:
        print('File contains no markers. Please add one as a bootstrap.\n' +
              'You can delete it later.')
        return

    if infile_name == '':
        print('Removing all markers')
        markers.clear()
        markers.set('name', 'shotcut:markers')

    else:
        # Re-assign existing marker numbers, and get a count for our additions
        marker_index = 0
        for marker in markers:
            marker.set('name', str(marker_index))
            marker_index = marker_index + 1

            marker_data = {}
            for item in marker.iter('property'):
                marker_data[item.get('name')] = item.text
            print( 'Existing marker %s at %s' % (marker_data.get('text'), marker_data.get('start')))

        # Append markers from the CSV
        # First line specifies the fields that are present
        # Defaults avoid error handling
        fields = ['#', 'Name', 'Start', 'End', 'Length', 'Color']
        with open(infile_name, newline='') as csvfile:
            csv_reader = csv.reader(csvfile, delimiter=',', quotechar='"')
            for row in csv_reader:
                if row[0] == '#':
                    # Header row tells which elements are present in the file
                    fields = row
                else:
                    # Parse the row into named items
                    row_data = {}
                    for ix in range(0, len(row)):
                        row_data[fields[ix]] = row[ix]

                    # Create an XML element and assign it a marker index
                    marker = ET.Element('properties')
                    marker.set('name', str(marker_index))
                    marker_index = marker_index + 1

                    sub = ET.SubElement(marker, 'property')
                    sub.set('name', 'text')
                    sub.text = row_data['Name']

                    # Time in the CSV is seconds.msec
                    # MLT wants HH:MM:SS.MSEC
                    mlt_time = seconds_as_hms( float(row_data['Start']) + time_shift_sec)
                    print( 'Adding marker from CSV at', mlt_time)

                    sub = ET.SubElement(marker, 'property')
                    sub.set('name', 'start')
                    sub.text = mlt_time

                    # End time is optional in the CSV
                    if row_data['End'] != '':
                        mlt_time = seconds_as_hms( float(row_data['End']) + time_shift_sec)

                    sub = ET.SubElement(marker, 'property')
                    sub.set('name', 'end')
                    sub.text = mlt_time

                    # Default color blue vs Shotcut's default green
                    sub = ET.SubElement(marker, 'property')
                    sub.set('name', 'color')
                    color = row_data['Color']
                    if color != '':
                        sub.text = '#' + color
                    else:
                        sub.text = '#000080'

                    markers.append(marker)

    # Output the new MLT file, saving a backup of the original
    ET.indent(tree)
    newname = outfile_name + '.new'
    tree.write(newname)

    backup_file = outfile_name + '.bak'
    try:
        os.remove(backup_file)
    except FileNotFoundError:
        pass
    os.rename(outfile_name, backup_file)
    os.rename(newname, outfile_name)


#==============================================================================
# Dump a Reaper-exported (or ReaperMarker.lua-created) marker .csv file
# First line specifies which elements are present: "End" through "Color"
# are optional
#
#  #,Name,Start,End,Length,Color
#  M1,Some text for marker 1,1536.000,,,008000
#       Color entered in Reaper as as 0,128,0)
#  M4,Marker Four,1692.423,,,
#       Default Marker color is red: 233,100,100)
#  M5,,1733.075,,,
#  M3,,1832.027,,,
#  M6,,1950.185,,,
#  M2,,2239.885,,,
#  R1,The first region,1757.318,1798.464,41.145,
#       Default region color is green: 0, 180, 0
#       Note the length is 1 msec less thatn End - Start
#
def dump_csv(infile_name):
    with open(infile_name, newline='') as csvfile:
        fields = ['#', 'Name', 'Start', 'End', 'Length', 'Color']
        csv_reader = csv.reader(csvfile, delimiter=',', quotechar='"')
        for row in csv_reader:
            if row[0] == '#':
                # Header row tells which elements are present
                for ix in range(0, len(row)):
                    print(ix, row[ix])
                fields = row
            else:
                for ix in range(0, len(row)):
                    print(fields[ix], row[ix])

#==============================================================================
# Dump any markers in a Reaper .rpp file
#
# Markers are individual lines at the level below <REAPER_PROJECT
# The source and purpose of the GUIDs is not clear.
# We may eventually DUMP markers from a .rpp, but not SET them: import a CSV
#
# Reaper marker editor has
# "Name" for the text
# "Position" for the Start time (or measure/beat)
# "ID" for the number
# "Set color..." to set color
# Region/Marker Manager also shows "End" and "Length"
#
#  MARKER 1 1536 "Some text for marker 1" 0 16809984 1 R {EEF44320-302A-4456-AE4C-11BC9CB9A33C} 0
#       16809984 = 0x1_00_80_00 is most likely the color
#  MARKER 4 1692.4235416666313 "Marker Four" 0 0 1 R {C4FE4C16-6FCE-4DCA-8875-2B4ADD1C2B3B} 0
#  MARKER 5 1733.0754553619558 "" 0 0 1 R {AD5CB9E0-4988-4F40-AEE0-DD8E6DDD7557} 0
#  MARKER 1 1757.3187883098401 "The first region" 9 0 1 R {36A7D31E-08C4-49F0-B7A2-C9502CC2150A} 0
#  MARKER 1 1798.4641591435989 "" 9
#       Region encoded as two MARKER with a "9" following the label, no GUID on end
#  MARKER 3 1832.0277708332944 "" 0 0 1 R {11F13DA5-0E1E-4D2B-8F22-6E34A37455FA} 0
#  MARKER 6 1950.1852800819488 "" 0 0 1 R {E8050711-B587-41EA-BCD6-BF8930EF7F81} 0
#  MARKER 2 2239.8855183983451 "" 0 0 1 R {F9E72F34-7660-41E7-BD94-5737488C23BD} 0
#
def dump_rpp(infile_name):
    print('Sorry: Reaper RPP files not supported. Use CSV import/export')
    return

#==============================================================================
def main():
    infile_name = ''
    outfile_name = ''

    if len(sys.argv) <= 1:
        print('marker-munger.py {infile}\n' +
              '  Dump markers from {infile}\n' +
              'marker-munger.py {infile.csv} {outfile.mlt} {offset}\n' +
              '  Merge markers from infile into outfile\n' +
              '  Optional signed offset in seconds.msec is added to CSV marker times.\n' +
              '  Offset is useful when a project uses multiple clips with their own CSV files.\n' +
              'marker-munger.py {infile.mlt} {outfile.csv}\n' +
              '  Dump markers from Shotcut infile as CSV outfile\n' +
              '  The CSV might then be imported by Reaper to aid audio editing.\n' +
              'files may be\n' +
              '  - .mlt for Shotcut project file\n' +
              '  - .csv for Reaper exported marker file')
        return

    if len(sys.argv) > 1:
        infile_name = sys.argv[1]
        
    if len(sys.argv) > 2:
        outfile_name = sys.argv[2]

    infile_spec  = os.path.splitext(infile_name)
    outfile_spec = os.path.splitext(outfile_name)

    time_shift_sec = 0.0
    if len(sys.argv) > 3:
        time_shift_sec = sys.argv[3]

    if infile_spec[1] == '.csv':
        if outfile_spec[1] == '.mlt':
            update_mlt(infile_name, outfile_name, float(time_shift_sec))
        else:
            dump_csv(infile_name)

    elif (sys.argv[1] == '-remove') and (outfile_spec[1] == '.mlt'):
        update_mlt('', outfile_name, 0.0)

    elif infile_spec[1] == '.mlt':
        if outfile_spec[1] == '.csv':
            dump_mlt_as_csv(infile_name, outfile_name)
        else:
            dump_mlt(infile_name)

    elif infile_spec[1] == '.rpp':
        dump_rpp(infile_name)

    else:
        print('ERROR: unsupported file type "' + infile_spec[1] + '"')

#==============================================================================
if __name__ == "__main__":    
    main()

