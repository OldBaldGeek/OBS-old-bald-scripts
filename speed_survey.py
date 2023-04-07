# Run a speed test every DT minutes and log the results
#
# Uses the speedtest-cli package
#
# 5 April 2023 by John Hartman

import speedtest
import datetime
import time

DT = 10

with open('speed_log.txt', 'a', encoding="utf-8") as f:
    f.write('Time, Latency msec, Download Kbps, Upload Kbps, Server\n')

    while True:
        try:
            st = speedtest.Speedtest()
            q = st.get_best_server()  # Get a server
            t = datetime.datetime.now().strftime("%d-%b-%Y %I:%M:%S %p")
            print(t + ' Test with', q['url'])
            dl = st.download()
            ul = st.upload()

            r = st.results
            f.write( t + ', ' + str( round(r.server['latency'],2) ) + ', ' +
                     str( round(r.download/1000, 2) ) + ', '+ 
                     str( round(r.upload/1000, 2) ) + ', ' +
                     r.server['url'] + '\n' )

        except KeyboardInterrupt as err:
            print('Exit by keyboard interupt')
            break;

        except Exception as err:
            msg = f"Speedtest failed with {err=}, {type(err)=}"
            f.write(msg + "\n")
            print(msg)

        f.flush()
        time.sleep(DT*60)

f.close()

