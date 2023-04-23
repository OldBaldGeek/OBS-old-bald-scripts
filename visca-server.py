# Simple web server to send VISCA messages to PTZ camera
#
# test with a sample json file
#   curl -X POST -H 'Content-Type: application/json'  -d @test.json http://localhost:8080/server
# May want to leave out the -H,: Window curl help doesn't list it
#   curl -X POST -i  -d @test.json http://localhost:8080/server
# shows response headers as well as data

# TODO: Python server prints a line for every request. Can we stop it?
#   127.0.0.1 - - [22/Apr/2023 12:06:18] "POST /server HTTP/1.1" 200 -
#   127.0.0.1 - - [22/Apr/2023 12:07:19] "GET /foo/ HTTP/1.1" 200 -

import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.parse
import serial
import json

# Default configuration values
g_hostName   = "localhost"
g_serverPort = 8080

# TODO: at 9600 baud, the 15-byte set-position takes 15.6 msec to send,
# and the 6-byte response another 6.25 msec.
# so we may want to try faster baud rates to increase our speed.
g_serialPort     = "COM1"
g_serialBaudRate = 9600

#==============================================================================
g_serial = None
g_lastError = None

# Byte arrays with message templates
#                                   0  1  2  3  4  5  6  7  8  9  10 11 12 13 14
g_get_position = bytearray.fromhex('80 09 06 12 FF')
g_set_position = bytearray.fromhex('80 01 06 02 00 00 00 00 00 00 00 00 00 00 FF')
g_get_zoom     = bytearray.fromhex('80 09 04 47 FF')
g_set_zoom     = bytearray.fromhex('80 01 04 47 00 00 00 00 FF')
g_slew         = bytearray.fromhex('80 01 06 01 00 00 03 03 FF')
g_zoom         = bytearray.fromhex('80 01 04 07 20 FF')
g_goto_preset  = bytearray.fromhex('80 01 04 3F 02 00 FF')
g_set_preset   = bytearray.fromhex('80 01 04 3F 01 00 FF')
g_version_inq  = bytearray.fromhex('80 09 00 02 FF')
#                   response GGGG    HHHH   JJJJ     KK
#                            vendor  model  version  max socket#

g_ack_complete = bytearray.fromhex('90 41 FF 90 51 FF')

#==============================================================================
# Set an error, return False
def set_error( a_errorString ):
    global g_lastError
    g_lastError = a_errorString
    return False

#==============================================================================
# Return the last error string
def last_error():
    global g_lastError
    return g_lastError

#==============================================================================
# Open the serial port
def init_serial(a_serialPort, a_serialBaudRate):
    try:
        retval = serial.Serial(a_serialPort, a_serialBaudRate, timeout=1, write_timeout=2)
        print(f'Opened serial port {a_serialPort} at {a_serialBaudRate} baud')
        return retval
    except Exception as exc:
        set_error(str(exc))
        return None

#==============================================================================
# Send the message a_bytes to the specified a_address
# return True/False, and a bytearrary with the reply if a_rxExpected is non-zero
def send_visca( a_address, a_bytes, a_rxExpected ):
    if g_serial is None:
        return set_error('Serial Port not open')

    # Discard any stale input
    g_serial.reset_input_buffer()

    a_bytes[0] = a_address + 0x80
    print('Sending', len(a_bytes), 'bytes:', a_bytes.hex())
    g_serial.write(a_bytes)

    if a_rxExpected != 0:
        # Reply data expected
        s = g_serial.read(a_rxExpected)
        print('Received', len(s), 'bytes:', s.hex())
        if len(s) != a_rxExpected:
            return set_error('Missing or incorrect serial response'), s
        return True, s
    else:
        # No data reply: should get Ack, Complete
        # 0  1  2  3  4  5
        # 90 41 FF 90 51 FF
        s = g_serial.read(6)
        print('Received Ack/Comp', len(s), 'bytes:', s.hex())
        if s != g_ack_complete:
            return set_error('Missing or incorrect serial response')

        return True

#==============================================================================
# Convert a 16-bit unsigned integer into a signed value
def as_signed( a_value ):
    if a_value >= 0x8000:
        return -(0x10000 - a_value)
    return a_value

#==============================================================================
# Convert a signed value into a 16-bit unsigned integer
def as_unsigned( a_value ):
    if a_value < 0:
        return (0x10000 + a_value)
    return a_value

#==============================================================================
# Get the current pan and tilt
def get_position( a_address ):
    # Expect a position reply:
    # 0  1  2  3  4  5  6  7  8  9  10
    # y0 50 0Y 0Y 0Y 0Y 0V 0V 0V 0V FF
    ok, ry = send_visca(a_address, g_get_position, 11)
    if ok and len(ry) >= 11:
        pan  = as_signed( (ry[2] << 12) | (ry[3] << 8) | (ry[4] << 4) | ry[5] )
        tilt = as_signed( (ry[6] << 12) | (ry[7] << 8) | (ry[8] << 4) | ry[9] )
        return True, pan, tilt

    return False, 0, 0

#==============================================================================
# Set the pan and tilt
def set_position( a_address, a_pan, a_tilt ):
    val = as_unsigned(a_pan)
    g_set_position[6] = (val >> 12) & 0x0F
    g_set_position[7] = (val >> 8)  & 0x0F
    g_set_position[8] = (val >> 4)  & 0x0F
    g_set_position[9] = (val)       & 0x0F
    
    val = as_unsigned(a_tilt)
    g_set_position[10] = (val >> 12) & 0x0F
    g_set_position[11] = (val >> 8)  & 0x0F
    g_set_position[12] = (val >> 4)  & 0x0F
    g_set_position[13] = (val)       & 0x0F

    # Expect Ack, Complete
    return send_visca(a_address, g_set_position, 0)

#==============================================================================
# Get the current zoom setting
def get_zoom( a_address ):
    # Expect a zoom reply:
    # 0  1  2  3  4  5  6 
    # y0 50 0Y 0Y 0Y 0Y FF
    ok, ry = send_visca(a_address, g_get_zoom, 7)
    if ok and len(ry) >= 7:
        zoom = (ry[2] << 12) | (ry[3] << 8) | (ry[4] << 4) | ry[5]
        return True, zoom

    return False, 0

#==============================================================================
# Set the zoom
def set_zoom( a_address, a_zoom ):
    val = as_unsigned(a_pan)
    g_set_zoom[6] = (val >> 12) & 0x0F
    g_set_zoom[7] = (val >> 8)  & 0x0F
    g_set_zoom[8] = (val >> 4)  & 0x0F
    g_set_zoom[9] = (val)       & 0x0F
    
    # Expect Ack, Complete
    return send_visca(a_address, g_set_zoom, 0)

#==============================================================================
# Start or stop pan or tilt: "up", "down", "left", "right", or "stop"
def do_slew( a_address, a_direction, a_speed ):
    g_slew[4] = 0x00
    g_slew[5] = 0x00
    g_slew[6] = 0x03
    g_slew[7] = 0x03
    if a_direction == 'up':
        g_slew[5] = int(a_speed)
        g_slew[7] = 0x01
    elif a_direction == 'down':
        g_slew[5] = int(a_speed)
        g_slew[7] = 0x02
    elif a_direction == 'left':
        g_slew[4] = int(a_speed)
        g_slew[6] = 0x01
    elif a_direction == 'right':
        g_slew[4] = int(a_speed)
        g_slew[6] = 0x02
    
    # Expect Ack, Complete
    return send_visca(a_address, g_slew, 0)

#==============================================================================
# Start or stop zoom: "in", "out", or "stop"
def do_zoom( a_address, a_direction, a_speed ):
    g_zoom[4] = 0x00
    if a_direction == 'in':
        g_zoom[4] = 0x20 + (int(a_speed) & 0x0F)
    elif a_direction == 'out':
        g_zoom[4] = 0x30 + (int(a_speed) & 0x0F)
    
    # Expect Ack, Complete
    return send_visca(a_address, g_zoom, 0)

#==============================================================================
# Select a preset (0 through N)
def goto_preset( a_address, a_preset ):
    g_goto_preset[5] = a_preset
    # Expect Ack, Complete
    return send_visca(a_address, g_goto_preset, 0)

#==============================================================================
# Program a preset (0 through N)
def set_preset( a_address, a_preset ):
    g_set_preset[5] = a_preset
    # Expect Ack, Complete
    return send_visca(a_address, g_set_preset, 0)

#==============================================================================
# Get the current pan and tilt
def get_version_info( a_address ):
    # Expect a position reply:
    # 0  1  2  3  4  5  6  7  8  9
    # y0 50 GG GG HH HH JJ JJ KK FF
    ok, ry = send_visca(a_address, g_version_inq, 10)
    if ok and len(ry) >= 11:
        vendor  = (ry[2] << 8) | ry[3]
        model   = (ry[4] << 8) | ry[5]
        version = (ry[6] << 8) | ry[7]
        socket  = ry[8]

        return True, vendor, model, version, socket

    return False, 0, 0, 0, 0

#==============================================================================
class MyServer(BaseHTTPRequestHandler):
    def send_error(self, a_error_code, a_error_string):
        self.send_response(a_error_code)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        self.wfile.write(bytes(a_error_string, "utf-8"))

    # Absolute set of pan and tilt, and/or zoom
    def do_cmd_moveto(self, a_post_body):
        camera = a_post_body.get("camera", "1")
        pan    = a_post_body.get("pan")
        tilt   = a_post_body.get("tilt")
        zoom   = a_post_body.get("zoom")

        # TODO: we COULD allow optional pan and tilt, reading current position
        if pan is not None and tilt is not None:
            if not set_position( camera, pan, tilt ):
                return '{"status":"' + last_error() + '"}'
        
        if zoom is not None:
            if not set_zoom( camera, zoom ):
                return '{"status":"' + last_error() + '"}'

        return '{"status":"ok"}'

    # Pan: slew or jog
    def do_cmd_pan(self, a_post_body):
        camera = a_post_body.get("camera", "1")
        pan    = a_post_body.get("value")
        speed  = a_post_body.get("speed",  "0")

        # pan may be left, right, or stop for slew operation
        # pan may be +N or -N for jog (relative to current position)
        if pan is None:
            return '{"status":"missing pan value"}'

        if (pan == 'left') or (pan == 'right') or (pan == 'stop'):
            if not do_slew( camera, pan, speed ):
                return '{"status":"' + last_error() + '"}'
        else:
            try:
                pan_num = int(pan)
                print("Pan is", str(pan_num))
            except:
                set_error('invalid pan value')
                return '{"status":"' + last_error() + '"}'

            # Read current position
            ok, pan_now, tilt_now = get_position( camera )
            if not ok:
                return '{"status":"' + last_error() + '"}'

            # Set updated position
            if not set_position( camera, pan_now + pan_num, tilt_now ):
                return '{"status":"' + last_error() + '"}'
        return '{"status":"ok"}'

    # Tilt: slew or jog
    def do_cmd_tilt(self, a_post_body):
        camera = a_post_body.get("camera", "1")
        tilt   = a_post_body.get("value")
        speed  = a_post_body.get("speed",  "0")
        
        # tilt may be up, down, or stop for slew operation
        # tilt may be +N or -N for jog (relative to current position)
        if tilt is None:
            return '{"status":"missing tilt value"}'

        if (tilt == 'up') or (tilt == 'down') or (tilt == 'stop'):
            if not do_slew( camera, tilt, speed ):
                return '{"status":"' + last_error() + '"}'
        else:
            try:
                tilt_num = int(tilt)
            except:
                set_error('invalid tilt value')
                return '{"status":"' + last_error() + '"}'

            # Read current position
            ok, pan_now, tilt_now = get_position( camera )
            if not ok:
                return '{"status":"' + last_error() + '"}'

            # Set updated position
            if not set_position( camera, pan_now, tilt_now + tilt_num ):
                return '{"status":"' + last_error() + '"}'
        return '{"status":"ok"}'

    # Zoom: slew or jog
    def do_cmd_zoom(self, a_post_body):
        camera = a_post_body.get("camera", "1")
        zoom   = a_post_body.get("value",)
        speed  = a_post_body.get("speed",  "0")

        # zoom may be left, right, or stop for slew operation
        # zoom may be +N or -N for jog (relative to current position)
        if zoom is None:
            return '{"status":"missing zoom value"}'

        if (zoom == 'in') or (zoom == 'out') or (zoom == 'stop'):
            if not do_zoom( camera, zoom, speed ):
                return '{"status":"' + last_error() + '"}'
        else:
            try:
                zoom_num = int(zoom)
                print("zoom is", str(zoom_num))
            except:
                set_error('invalid zoom value')
                return '{"status":"' + last_error() + '"}'

            # Read current zoom
            ok, zoom_now = get_zoom( camera )
            if not ok:
                return '{"status":"' + last_error() + '"}'

            # Set updated position
            if not set_zoom( camera, zoom_now + zoom_num ):
                return '{"status":"' + last_error() + '"}'
        return '{"status":"ok"}'

    # Goto preset
    def do_cmd_go_preset(self, a_post_body):
        camera = a_post_body.get("camera", "1")
        value = a_post_body.get("value")
        if value is None:
            return '{"status":"missing preset value"}'

        if not goto_preset( camera, value ):
            return '{"status":"' + last_error() + '"}'
        return '{"status":"ok"}'

    # Set preset
    def do_cmd_set_preset(self, a_post_body):
        camera = a_post_body.get("camera", "1")
        value = a_post_body.get("value")
        if value is None:
            return '{"status":"missing preset value"}'

        if not set_preset( camera, value ):
            return '{"status":"' + last_error() + '"}'
        return '{"status":"ok"}'

    # Report camera position and zoom
    def do_cmd_report(self, a_post_body):
        camera = a_post_body.get("camera", "1")

        # Read current position
        ok, pan_now, tilt_now = get_position( camera )
        if not ok:
            return '{"status":"' + last_error() + '"}'

        # Read current zoom
        ok, zoom_now = get_zoom( camera )
        if not ok:
            return '{"status":"' + last_error() + '"}'

        # Generate json response
        response = {}
        response['status'] = "ok"
        response['camera'] = camera
        response['pan']    = pan_now
        response['tilt']   = tilt_now
        response['zoom']   = zoom_now
        return json.dumps(response, indent=4)

    # Get the current pan and tilt
    def do_cmd_version_info(self, a_post_body):
        camera = a_post_body.get("camera", "1")
        ok, vendor, model, version, max_socket = get_version_info(camera)
        if not ok:
            return '{"status":"' + last_error() + '"}'

        # Generate json response
        response = {}
        response['status']     = "ok"
        response['camera']     = camera
        response['vendor']     = vendor
        response['model']      = model
        response['version']    = version
        response['max_socket'] = max_socket
        return json.dumps(response, indent=4)

    #==============================================================================
    def do_GET(self):
        # For now, ignore the path and just send a generic page
        # TODO: maybe add version, serial port, baud rate...
        # Show persistent errors lie no serial port.
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        str = """<html><head><title>Visca Server</title></head><body>
        <p>This is the Cabrini Visca server.</p>
        </body></html>
        """
        self.wfile.write(bytes(str, "utf-8"))

    #==============================================================================
    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        print("POST to path", url.path)
        if url.path != '/server':
            self.send_error(404, 'not found')
            return

        # Get the body of the request
        # TODO: if no Content-length, read all?
        content_len = int(self.headers.get('Content-Length'))
        print('POST with ' + str(content_len) + ' bytes')
        post_body = json.loads(self.rfile.read(content_len))
        print(json.dumps(post_body, indent=4))
        
        command = post_body.get('command', '?')
        if command == 'moveto':
            response = self.do_cmd_moveto(post_body)
        elif command == 'pan':
            response = self.do_cmd_pan(post_body)
        elif command == 'tilt':
            response = self.do_cmd_tilt(post_body)
        elif command == 'zoom':
            response = self.do_cmd_zoom(post_body)

        elif command == 'go-preset':
            response = self.do_cmd_go_preset(post_body)
        elif command == 'set-preset':
            response = self.do_cmd_set_preset(post_body)

        elif command == 'report':
            response = self.do_cmd_report(post_body)
        elif command == 'version_info':
            response = self.do_cmd_version_info(post_body)

        else:
            response = '{"status":"unknown command"}'

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(bytes(response, "utf-8"))

#==============================================================================
def main():
    global g_serialPort
    global g_serialBaudRate
    global g_serverPort
    global g_serial

    if (len(sys.argv) <= 1):
        print( 'visca-server.py {serial port} {baud rate] {TCP port}')
        print( '  parameters are optional' )
        print( '  - {serial port} serial port for VISCA. Default COM1' )
        print( '  - {baud rate}   serial baud rate. Default 9600' )
        print( '  - {baud rate}   HTTP port. Default 8080' )

    if (len(sys.argv) > 1):
        g_serialPort = sys.argv[1]
        
    if (len(sys.argv) > 2):
        g_serialBaudRate = int(sys.argv[2])

    if (len(sys.argv) > 3):
        g_serverPort = int(sys.argv[3])

    # Open the serial port
    g_serial = init_serial(g_serialPort, g_serialBaudRate)

    # Start the web sserver
    webServer = HTTPServer((g_hostName, g_serverPort), MyServer)
    print("VISCA Server started http://%s:%d" % (g_hostName, g_serverPort))

    try:
        webServer.serve_forever()
    except KeyboardInterrupt:
        pass

    webServer.server_close()
    print("Server stopped.")

#==============================================================================
if __name__ == "__main__":    
    main()

