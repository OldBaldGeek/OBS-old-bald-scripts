# Run a speed test every DT minutes and log the results
#
# Uses the speedtest-cli package
#
# 8 April 2023 by John Hartman

import sys
import speedtest
import datetime
import time

# Output to file
def do_output(a_filename, a_str):
    with open(a_filename, 'a', encoding="utf-8") as f:
        f.write(a_str + '\n')
        f.flush()
        f.close()

def main():
    print( 'speed_survey version 2.0: internet speed test' )

    DT = -1        # once only
    outfile = None # don't log to file

    if (len(sys.argv) > 1):
        try:
            DT = float(sys.argv[1])
        except ValueError:
            print( 'speed_survey.py {deltaSeconds} {outfile}')
            print( '  parameters are optional' )
            print( '  - no parameters: do one test, log to console')
            print( '  - {deltaSeconds} specifies time in seconds between tests' )
            print( '  - {outfile}      specifies a filename for output. Omit for console.' )
            return

    if (len(sys.argv) > 2):
        outfile = sys.argv[2]
        do_output(outfile, 'Time, Latency msec, Download kbps, Upload kbps, Server')

    while True:
        try:
            st = speedtest.Speedtest()
            q = st.get_best_server()  # Get a server
            t = datetime.datetime.now().strftime("%d-%b-%Y %I:%M:%S %p")
            print(t + '. Test with', q['url'])

            dl = st.download()
            ul = st.upload()
            r = st.results

            if (outfile != None):
                do_output( outfile, 
                           f"{t}, {r.server['latency']:.2f}, " +
                           f"{r.download/1000:.0f}, {r.upload/1000:.0f}, " +
                           r.server['url'] )

            print( f"   Latency {r.server['latency']:.2f} msec, " +
                   f"Download {r.download/1000:.0f} kbps, " +
                   f"Upload {r.upload/1000:.0f} kbps" )

        except KeyboardInterrupt as err:
            print('Exit by keyboard interupt')
            break;

        except Exception as err:
            msg = f"Speedtest failed with {err=}"
            if (outfile != None):
                do_output(msg)
            print(msg)

        if (DT < 0):
            break;

        time.sleep(DT)

if __name__ == "__main__":
   main()
