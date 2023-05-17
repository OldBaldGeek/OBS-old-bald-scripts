# Simple web server to send VISCA messages to PTZ camera
#
# test with a sample json file
#   curl -X POST -i -d @test.json http://localhost:8080/server
# -i shows response headers as well as data

# TODO: Python server prints a line for every request. Can we stop it?
#   127.0.0.1 - - [22/Apr/2023 12:06:18] "POST /server HTTP/1.1" 200 -
#   127.0.0.1 - - [22/Apr/2023 12:07:19] "GET /foo/ HTTP/1.1" 200 -
#
# We define "right", "up, etc. to be as seen by the camera. Thus:
# - "left" is increasing Camera pan
# - "up" is increasing Camera tilt
# - "in" is increasing Camera zoom

import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.parse
import serial
import json

g_version = "1.3"

# Default configuration values overrideable by commandline parameters.
# Originally had hostname = "localhost" here and in the Javascript client.
# But Chrome sent some requests as IPv6, causing slowdown.
g_hostName   = "127.0.0.1"
g_serverPort = 8080
g_serialPort     = "COM1"
g_serialBaudRate = 9600
# At 9600 baud, a 15-byte set-position takes 15.6 msec to send,
# and the 6-byte response another 6.25 msec.
# so we may want to try faster baud rates to increase our speed.

g_viscaTalker = None

#==============================================================================
# Error reporting exception
class ErrorEx(Exception):
    def __init__(self, a_error):
        self.errors = [a_error]

    def add(self, a_error):
        self.errors.append(a_error)

    def get_errors(self):
        return self.errors

#==============================================================================
# Low-level VISCA functions
class ViscaTalker:
    def __init__(self, a_serialPort, a_serialBaudRate):
        self.serial_port = None
        if a_serialPort == 'SIM':
            print(f'Using simulated serial port')
        else:
            try:
                self.serial_port = serial.Serial(a_serialPort, a_serialBaudRate,
                                                 timeout=1, write_timeout=2)
                print(f'Opened serial port {a_serialPort} at {a_serialBaudRate} baud')
            except serial.SerialException as exc:
                raise ErrorEx(str(exc))

        # Byte arrays with message templates
        # Some bytes are overwritten by functions which use them, so be careful
        #                                            0  1  2  3  4  5  6  7  8  9  10 11 12 13 14
        self.visca_get_position = bytearray.fromhex('80 09 06 12 FF')
        self.visca_set_position = bytearray.fromhex('80 01 06 02 00 00 00 00 00 00 00 00 00 00 FF')
        self.visca_get_zoom     = bytearray.fromhex('80 09 04 47 FF')
        self.visca_set_zoom     = bytearray.fromhex('80 01 04 47 00 00 00 00 FF')
        self.visca_slew         = bytearray.fromhex('80 01 06 01 00 00 03 03 FF')
        self.visca_zoom         = bytearray.fromhex('80 01 04 07 20 FF')
        self.visca_goto_preset  = bytearray.fromhex('80 01 04 3F 02 00 FF')
        self.visca_set_preset   = bytearray.fromhex('80 01 04 3F 01 00 FF')
        self.visca_version_inq  = bytearray.fromhex('80 09 00 02 FF')

        self.visca_ack_complete = bytearray.fromhex('90 41 FF 90 51 FF')

    # Send the message a_bytes to the specified a_address
    # return a bytearrary with the reply if a_rxExpected is non-zero
    # Throws ErrorEx on failure
    def send_visca(self, a_address, a_bytes, a_rxExpected):
        a_bytes[0] = int(a_address) + 0x80
        if self.serial_port is None:
            print('Simulate sending', len(a_bytes), 'bytes:', a_bytes.hex(' '))
            if a_rxExpected != 0:
                # Reply data expected
                s = bytearray(a_rxExpected)
                print('Simulate receiving', a_rxExpected, 'bytes:', s.hex(' '))
                return s

        else:
            # Discard any stale input before we send
            self.serial_port.reset_input_buffer()
            print('Sending', len(a_bytes), 'bytes:', a_bytes.hex(' '))
            self.serial_port.write(a_bytes)

            s = self.serial_port.timeout = 1    # 1-second normal timeout
            if a_rxExpected != 0:
                # Reply data expected
                s = self.serial_port.read(a_rxExpected)
                print('Received', len(s), 'bytes:', s.hex(' '))
                if len(s) != a_rxExpected:
                    raise ErrorEx('Incorrect serial response: ' + s.hex(' '))
                return s
            else:
                # No data reply: should get Ack, Completion
                #   0  1  2   3  4  5
                #   X0 4s FF  X0 5s FF
                # where "X" is the remote address | 8 and s is the socket number.
                s = self.serial_port.read(6)
                got = len(s)
                print('Received Ack/Comp', got, 'bytes:', s.hex(' '))
                repAddr = (int(a_address) | 8) << 4
                if (got < 3) or (s[0] != repAddr) or ((s[1] & 0xF0) != 0x40):
                    raise ErrorEx('Expected Ack, got ' + s.hex(' '))

                # Aver VC520+ returns Completion immediately for all commands.
                # Vaddio HD-20 may delay Completion until the command is done,
                # which could be 10 seconds for a long pan at slow speed.
                # (Oddly, HD-20 delays Completion for goto-preset, but NOT for
                # move-absolute, which may take just as long.)
                if got < 6:
                    # Try to read the remaining bytes using a long timeout.
                    # (Timeout is reset before the next read)
                    self.serial_port.timeout = 20
                    s = s + self.serial_port.read(6 - got)
                    print('  Then received', len(s), 'bytes:', s.hex(' '))

                if (len(s) < 6) or (s[3] != repAddr) or ((s[4] & 0xF0) != 0x50):
                    raise ErrorEx('Expected Completion, got ' + s.hex(' '))

    #===========================================================================
    # Validate a string or integer parameter value as an integer
    # Throw ErrorEx if not
    def parm_as_int(self, a_value):
        try:
            val = int(a_value)
            return val
        except:
            raise ErrorEx('Expected integer value')

    #===========================================================================
    # Convert a 16-bit unsigned integer from a VISCA response into a signed value
    def as_signed(self, a_value):
        if a_value >= 0x8000:
            return -(0x10000 - a_value)
        return a_value

    #===========================================================================
    # Convert a signed parameter value into a 16-bit value for a VISCA buffer
    def signed_parm_as_unsigned(self, a_value):
        val = self.parm_as_int(a_value)
        if val < 0:
            return (0x10000 + val)
        return val

    #===========================================================================
    # Get the current pan and tilt
    # Throws ErrorEx on failure
    def get_position(self, a_address):
        # Expect a position reply:
        # 0  1  2  3  4  5  6  7  8  9  10
        # y0 50 0Y 0Y 0Y 0Y 0V 0V 0V 0V FF
        try:
            ry = self.send_visca(a_address, self.visca_get_position, 11)
        except ErrorEx as ex:
            ex.add('get_position failed')
            raise

        pan  = self.as_signed( (ry[2] << 12) | (ry[3] << 8) | (ry[4] << 4) | ry[5] )
        tilt = self.as_signed( (ry[6] << 12) | (ry[7] << 8) | (ry[8] << 4) | ry[9] )
        return pan, tilt

    #===========================================================================
    # Set the pan and tilt
    # Throws ErrorEx on failure
    def set_position(self, a_address, a_pan, a_tilt, a_speed):
        # Sony docs say speed is [4], and [5] is 0
        # Aver docs say [4] and [5] both 0
        # Vaddio HD-20 docs say pan-speed is [5], tilt-speed [4], but
        # HD-20 may reverse them. Test shows HD-20 actually uses [4]
        self.visca_set_position[4] = self.parm_as_int(a_speed)
        self.visca_set_position[5] = self.parm_as_int(a_speed)

        val = self.signed_parm_as_unsigned(a_pan)
        self.visca_set_position[6] = (val >> 12) & 0x0F
        self.visca_set_position[7] = (val >> 8)  & 0x0F
        self.visca_set_position[8] = (val >> 4)  & 0x0F
        self.visca_set_position[9] = (val)       & 0x0F

        val = self.signed_parm_as_unsigned(a_tilt)
        self.visca_set_position[10] = (val >> 12) & 0x0F
        self.visca_set_position[11] = (val >> 8)  & 0x0F
        self.visca_set_position[12] = (val >> 4)  & 0x0F
        self.visca_set_position[13] = (val)       & 0x0F

        # Expect Ack, Complete
        try:
            self.send_visca(a_address, self.visca_set_position, 0)
        except ErrorEx as ex:
            ex.add('set_position failed')
            raise

    #===========================================================================
    # Get the current zoom setting
    # Throws ErrorEx on failure
    def get_zoom(self, a_address):
        # Expect a zoom reply:
        # 0  1  2  3  4  5  6
        # y0 50 0Y 0Y 0Y 0Y FF
        try:
            ry = self.send_visca(a_address, self.visca_get_zoom, 7)
        except ErrorEx as ex:
            ex.add('get_zoom failed')
            raise

        zoom = (ry[2] << 12) | (ry[3] << 8) | (ry[4] << 4) | ry[5]
        return zoom

    #===========================================================================
    # Set the zoom
    # Throws ErrorEx on failure
    def set_zoom(self, a_address, a_zoom):
        try:
            val = self.parm_as_int(a_zoom)
            self.visca_set_zoom[4] = (val >> 12) & 0x0F
            self.visca_set_zoom[5] = (val >> 8)  & 0x0F
            self.visca_set_zoom[6] = (val >> 4)  & 0x0F
            self.visca_set_zoom[7] = (val)       & 0x0F
            self.send_visca(a_address, self.visca_set_zoom, 0)
        except ErrorEx as ex:
            ex.add('set_zoom failed')
            raise

    #===========================================================================
    # Start or stop pan and/or tilt: direction is up/down/left/right/stop. Speed as desired
    # Throws ErrorEx on failure
    def do_slew(self, a_address, a_pan_direction, a_pan_speed, a_tilt_direction, a_tilt_speed):
        try:
            # Sony and Aver docs say pan-speed is [4] (though Aver VC520+ ignores speed)
            # Vaddio HD-20 docs say pan-speed is [5], but HD-20 actually uses [4].
            self.visca_slew[4] = self.parm_as_int(a_pan_speed)
            if a_pan_direction == 'left':
                self.visca_slew[6] = 0x01
            elif a_pan_direction == 'right':
                self.visca_slew[6] = 0x02
            elif a_pan_direction == 'stop':
                self.visca_slew[6] = 0x03
                self.visca_slew[4] = 0
            else:
                raise ErrorEx('Invalid pan direction')

            self.visca_slew[5] = self.parm_as_int(a_tilt_speed)
            if a_tilt_direction == 'up':
                self.visca_slew[7] = 0x01
            elif a_tilt_direction == 'down':
                self.visca_slew[7] = 0x02
            elif a_tilt_direction == 'stop':
                self.visca_slew[7] = 0x03
                self.visca_slew[5] = 0
            else:
                raise ErrorEx('Invalid tilt direction')

            self.send_visca(a_address, self.visca_slew, 0)
        except ErrorEx as ex:
            ex.add('do_slew failed')
            raise

    #===========================================================================
    # Start or stop zoom: "in", "out", or "stop"
    # Throws ErrorEx on failure
    def do_zoom(self, a_address, a_direction, a_speed):
        try:
            if a_direction == 'in':
                self.visca_zoom[4] = 0x20 + (int(a_speed) & 0x0F)
            elif a_direction == 'out':
                self.visca_zoom[4] = 0x30 + (int(a_speed) & 0x0F)
            elif a_direction == 'stop':
                self.visca_zoom[4] = 0x00
            else:
                raise ErrorEx('Invalid zoom direction')

            self.send_visca(a_address, self.visca_zoom, 0)
        except ErrorEx as ex:
            ex.add('do_zoom failed')
            raise

    #===========================================================================
    # Select a preset (0 through N)
    # Throws ErrorEx on failure
    def goto_preset(self, a_address, a_preset):
        try:
            val = self.parm_as_int(a_preset)
            self.visca_goto_preset[5] = val
            self.send_visca(a_address, self.visca_goto_preset, 0)

        except ErrorEx as ex:
            ex.add('goto_preset failed')
            raise

    #===========================================================================
    # Program a preset (0 through N)
    # Throws ErrorEx on failure
    def set_preset(self, a_address, a_preset):
        try:
            val = self.parm_as_int(a_preset)
            self.visca_set_preset[5] = val
            self.send_visca(a_address, self.visca_set_preset, 0)
        except ErrorEx as ex:
            ex.add('set_preset failed')
            raise

    #===========================================================================
    # Get the current pan and tilt
    # Throws ErrorEx on failure
    def get_version_info(self, a_address):
        # Expect a position reply:
        # 0  1  2  3  4  5  6  7  8  9
        # y0 50 GG GG HH HH JJ JJ KK FF
        try:
            ry = self.send_visca(a_address, self.visca_version_inq, 10)
        except ErrorEx as ex:
            ex.add('get_version_info failed')
            raise

        vendor  = (ry[2] << 8) | ry[3]
        model   = (ry[4] << 8) | ry[5]
        version = (ry[6] << 8) | ry[7]
        socket  = ry[8]
        return vendor, model, version, socket

#==============================================================================
class MyServer(BaseHTTPRequestHandler):

    #===========================================================================
    def send_html(self, a_result_code, a_string):
        self.send_response(a_result_code)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        self.wfile.write(bytes(a_string, "utf-8"))

    #===========================================================================
    def send_post(self, a_result_code, a_string):
        self.send_response(a_result_code)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        self.wfile.write(bytes(a_string, "utf-8"))

    #===========================================================================
    # Absolute set of pan and tilt, and/or zoom
    def do_cmd_moveto(self, a_post_body):
        response = {}
        response['status'] = 'fail'

        camera = a_post_body.get("camera", "1")
        pan    = a_post_body.get("pan")
        tilt   = a_post_body.get("tilt")
        zoom   = a_post_body.get("zoom")
        speed  = a_post_body.get("speed",  "0")

        try:
            if pan is not None and tilt is not None:
                g_viscaTalker.set_position( camera, pan, tilt, speed )
            if zoom is not None:
                g_viscaTalker.set_zoom( camera, zoom )
            response['status'] = 'ok'

        except ErrorEx as ex:
            response['errors'] = ex.get_errors()

        return response

    #===========================================================================
    # Slew (pan and tilt together)
    def do_cmd_slew(self, a_post_body):
        response = {}
        response['status'] = 'fail'

        camera      = a_post_body.get("camera", "1")
        pan         = a_post_body.get("pan-value")
        tilt        = a_post_body.get("tilt-value")
        pan_speed   = a_post_body.get("pan-speed", 0)
        tilt_speed  = a_post_body.get("tilt-speed", 0)

        if (pan is None) and (tilt is None):
            response['errors'] = ["missing pan or tilt direction"]
        else:
            try:
                g_viscaTalker.do_slew(camera, pan, pan_speed, tilt, tilt_speed)
                response['status'] = 'ok'

            except ErrorEx as ex:
                response['errors'] = ex.get_errors()

        return response

    #===========================================================================
    # Pan: slew or jog
    def do_cmd_pan(self, a_post_body):
        response = {}
        response['status'] = 'fail'

        camera = a_post_body.get("camera", "1")
        pan    = a_post_body.get("value")
        speed  = a_post_body.get("speed", 0)

        # pan may be left, right, or stop for slew operation
        # pan may be +N or -N for jog (relative to current position)
        if pan is None:
            response['errors'] = ["missing pan value"]
        else:
            try:
                if (pan == 'left') or (pan == 'right') or (pan == 'stop'):
                    g_viscaTalker.do_slew(camera, pan, speed, 'stop', 0)
                else:
                    try:
                        pan_num = int(pan)
                    except:
                        raise ErrorEx('invalid pan value')

                    # Read current position
                    pan_now, tilt_now = g_viscaTalker.get_position( camera )
                    # Set updated position
                    g_viscaTalker.set_position( camera, pan_now + pan_num, tilt_now, speed )

                response['status'] = 'ok'

            except ErrorEx as ex:
                response['errors'] = ex.get_errors()

        return response

    #===========================================================================
    # Tilt: slew or jog
    def do_cmd_tilt(self, a_post_body):
        response = {}
        response['status'] = 'fail'

        camera = a_post_body.get("camera", "1")
        tilt   = a_post_body.get("value")
        speed  = a_post_body.get("speed", 0)
        
        # tilt may be up, down, or stop for slew operation
        # tilt may be +N or -N for jog (relative to current position)
        if tilt is None:
            response['errors'] = ["missing tilt value"]
        else:
            try:
                if (tilt == 'up') or (tilt == 'down') or (tilt == 'stop'):
                    g_viscaTalker.do_slew( camera, 'stop', 0, tilt, speed )
                else:
                    try:
                        tilt_num = int(tilt)
                    except:
                        raise ErrorEx('invalid tilt value')

                    # Read current position
                    pan_now, tilt_now = g_viscaTalker.get_position( camera )
                    # Set updated position
                    g_viscaTalker.set_position( camera, pan_now, tilt_now + tilt_num, speed )

                response['status'] = 'ok'

            except ErrorEx as ex:
                response['errors'] = ex.get_errors()

        return response

    #===========================================================================
    # Zoom: slew or jog
    def do_cmd_zoom(self, a_post_body):
        response = {}
        response['status'] = 'fail'

        camera = a_post_body.get("camera", "1")
        zoom   = a_post_body.get("value")
        speed  = a_post_body.get("speed",  "0")

        # zoom may be left, right, or stop for slew operation
        # zoom may be +N or -N for jog (relative to current position)
        try:
            if zoom is None:
                raise ErrorEx('missing zoom value')

            if (zoom == 'in') or (zoom == 'out') or (zoom == 'stop'):
                g_viscaTalker.do_zoom( camera, zoom, speed )
            else:
                try:
                    zoom_num = int(zoom)
                except:
                    raise ErrorEx('invalid zoom value')

                # Read current zoom
                zoom_now = g_viscaTalker.get_zoom( camera )
                # Set updated position
                g_viscaTalker.set_zoom( camera, zoom_now + zoom_num )

            response['status'] = 'ok'

        except ErrorEx as ex:
            response['errors'] = ex.get_errors()

        return response

    #===========================================================================
    # Goto preset
    def do_cmd_go_preset(self, a_post_body):
        response = {}
        response['status'] = 'fail'

        camera = a_post_body.get("camera", "1")
        value = a_post_body.get("value")

        try:
            if value is None:
                raise ErrorEx('missing preset value')
            g_viscaTalker.goto_preset( camera, value )
            response['status'] = "ok"

        except ErrorEx as ex:
            response['errors'] = ex.get_errors()

        return response

    #===========================================================================
    # Set preset
    def do_cmd_set_preset(self, a_post_body):
        response = {}
        response['status'] = 'fail'

        camera = a_post_body.get("camera", "1")
        value = a_post_body.get("value")

        try:
            if value is None:
                raise ErrorEx('missing preset value')
            g_viscaTalker.set_preset( camera, value )
            response['status'] = "ok"

        except ErrorEx as ex:
            response['errors'] = ex.get_errors()

        return response

    #===========================================================================
    # Report camera position and zoom
    def do_cmd_report(self, a_post_body):
        response = {}
        response['status'] = 'fail'
        camera = a_post_body.get("camera", "1")

        try:
            # Read current position
            pan_now, tilt_now = g_viscaTalker.get_position( camera )
            # Read current zoom
            zoom_now = g_viscaTalker.get_zoom( camera )
            response['status'] = "ok"
            response['camera'] = camera
            response['pan']    = pan_now
            response['tilt']   = tilt_now
            response['zoom']   = zoom_now

        except ErrorEx as ex:
            response['errors'] = ex.get_errors()

        return response

    #===========================================================================
    # Get camera information
    def do_cmd_version_info(self, a_post_body):
        response = {}
        response['status'] = 'fail'
        camera = a_post_body.get("camera", "1")

        try:
            vendor, model, version, max_socket = g_viscaTalker.get_version_info(camera)
            response['status']     = "ok"
            response['camera']     = camera
            response['vendor']     = vendor
            response['model']      = model
            response['version']    = version
            response['max_socket'] = max_socket
        except ErrorEx as ex:
            response['errors'] = ex.get_errors()

        return response

    #===========================================================================
    # Report basic servier information
    def do_cmd_about(self, a_post_body):
        global g_version
        global g_serialPort
        global g_serialBaudRate

        response = {}
        response['status']    = 'ok'
        response['version']   = g_version
        response['port']      = g_serialPort
        response['baud_rate'] = g_serialBaudRate
        return response

    #===========================================================================
    # Send a string of bytes
    def do_cmd_send_raw(self, a_post_body):
        response = {}
        response['status'] = 'fail'
        camera = a_post_body.get("camera", "1")
        data = a_post_body.get("bytes-to-send")
        print(data)
        bytes_to_send = bytearray.fromhex(data)
        bytes_to_send.insert(0,0)   # space for the address
        expected_reply = int(a_post_body.get("reply-length", 0))
        try:
            if bytes_to_send == None:
                raise ErrorEx('missing bytes to send')

            if expected_reply == 0:
                g_viscaTalker.send_visca(camera, bytes_to_send, expected_reply)
                response['response-bytes'] = ''
            else:
                s = g_viscaTalker.send_visca(camera, bytes_to_send, expected_reply)
                response['response-bytes'] = s.hex(' ')

            response['status'] = "ok"
        except ErrorEx as ex:
            response['errors'] = ex.get_errors()

        return response

    #==============================================================================
    # Add headers to deal with CORS
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'OPTIONS, GET, POST')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        return super(MyServer, self).end_headers()

    #==============================================================================
    # Accept OPTIONS to deal with CORS
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Allow', 'OPTIONS, GET, POST')
        self.end_headers()

    #==============================================================================
    def do_GET(self):
        global g_version
        global g_serialPort
        global g_serialBaudRate

        # For now, ignore the path and just send a generic page
        # TODO: maybe add number of good and failed requests
        # Show persistent errors like no serial port.
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        val = "<html><head><title>Visca Server</title></head><body>" +\
              "<p>This is the Cabrini Visca server.</p>" +\
              "<p>Version: " + g_version + "</p>" +\
              "<p>Serial interface: " + g_serialPort +\
              " at " + str(g_serialBaudRate) + " baud.</p>" +\
              "</body></html>";
        self.wfile.write(bytes(val, "utf-8"))

    #==============================================================================
    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        #print("POST to path", url.path)
        if url.path != '/server':
            self.send_html(404, 'not found')
            return

        # Get the body of the request
        # TODO: if no Content-length, read all?
        content_len = int(self.headers.get('Content-Length'))
        #print('Received POST with ' + str(content_len) + ' bytes')
        post_body = json.loads(self.rfile.read(content_len))
        #print(json.dumps(post_body, indent=4))
        
        command = post_body.get('command', '?')
        if command == 'pan':
            response = self.do_cmd_pan(post_body)
        elif command == 'tilt':
            response = self.do_cmd_tilt(post_body)
        elif command == 'slew':
            response = self.do_cmd_slew(post_body)
        elif command == 'zoom':
            response = self.do_cmd_zoom(post_body)
        elif command == 'moveto':
            response = self.do_cmd_moveto(post_body)

        elif command == 'go-preset':
            response = self.do_cmd_go_preset(post_body)
        elif command == 'set-preset':
            response = self.do_cmd_set_preset(post_body)

        elif command == 'report':
            response = self.do_cmd_report(post_body)
        elif command == 'version-info':
            response = self.do_cmd_version_info(post_body)
        elif command == 'about':
            response = self.do_cmd_about(post_body)
        elif command == 'send_raw':
            response = self.do_cmd_send_raw(post_body)

        else:
            response = {"status":"fail", "errors":"unknown command"}

        response_string = json.dumps(response, indent=4)

        #print('Send response')
        #print(response_string)

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.send_header("Content-Length", str(len(response_string)))
        self.end_headers()
        self.wfile.write(bytes(response_string, "utf-8"))

#==============================================================================
def main():
    global g_hostname
    global g_serialPort
    global g_serialBaudRate
    global g_serverPort
    global g_viscaTalker

    if (len(sys.argv) <= 1):
        print( 'visca-server.py {serial port} {baud rate] {TCP port}')
        print( '  parameters are optional' )
        print( '  - {serial port} serial port for VISCA. Default COM1' )
        print( '    Specify SIM for simulated operation.' )
        print( '  - {baud rate}   serial baud rate. Default 9600' )
        print( '  - {port}        HTTP port. Default 8080' )

    if (len(sys.argv) > 1):
        g_serialPort = sys.argv[1]
        
    if (len(sys.argv) > 2):
        g_serialBaudRate = int(sys.argv[2])

    if (len(sys.argv) > 3):
        g_serverPort = int(sys.argv[3])

    g_viscaTalker = ViscaTalker(g_serialPort, g_serialBaudRate)

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

