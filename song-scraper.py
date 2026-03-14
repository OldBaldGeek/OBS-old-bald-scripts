#!/usr/bin/python
# Scrape John's song usage text file into a CSV
#
# Bad Python by John Hartman
#

import os
import sys
import re
import csv
from datetime import datetime

g_version = "2.1"   # include only dates g_first_date
# 6/13/2021 is the date of the first livestreamed Mass. Earlier were on Zoom
g_first_date = datetime(2021, 6, 13)

#==============================================================================
def get_dates( a_string ):
    dates = re.findall(r"\d{1,2}/\d{1,2}/\d{2,4}", a_string)
    return dates

#==============================================================================
class SongInfo():
    def __init__(self):
        self.dump(None)

    # Dump any pending data, reset for new usage
    def dump(self, a_writer):
        if (a_writer != None) and (self.title != ''):
            # Convert the list of dates into a string
            dates_string = ''
            for d in self.dates:
                dstr = d.strftime('%m/%d/%Y')
                if dates_string == '':
                    dates_string = dstr
                else:
                    dates_string += ', ' + dstr

            csv_row = [ self.title, self.book, 
                        len(self.dates), dates_string, self.raw_data ]
            a_writer.writerow(csv_row)

        self.title = ''
        self.book  = ''
        self.dates = []
        self.raw_data = ''

    def set_title(self, a_title):
        self.title = a_title.strip().replace('"', "'")

    def set_book(self, a_book):
        self.book = a_book.strip().replace('"', "'")

    def add_dates(self, a_dates):
            for date_string in a_dates:
                d = datetime.strptime(date_string, '%m/%d/%Y')
                if d >= g_first_date:
                    self.dates.append( d )

    def add_raw_line(self, a_line):
        self.raw_data += a_line

#==============================================================================
def main():

    if len(sys.argv) < 2:
        print('Process John\'s list of Cabrini song usage to generate a CSV\n' +
              'Usage:\n' +
              '  song-scraper.py {usagefile.txt}')
        return

    print('song-scraper.py version ', g_version)
    infile_name = sys.argv[1]
    infile_spec = os.path.splitext(infile_name)
    outfile_name = infile_spec[0] + '.csv'

    with open(infile_name, 'r',  encoding='utf-8') as infile:
        with open(outfile_name, 'w', newline='') as csvfile:
            start_date = g_first_date.strftime('%m/%d/%Y')
            writer = csv.writer(csvfile)
            writer.writerow(['Title', 'Book/Source',
                             'Times Used Since ' + start_date, 'Dates Used Since ' + start_date,
                             'Raw Data (usually multi-line)'])

            lines = infile.readlines()
            line_number = 1
            in_song_list = False
            song_info = SongInfo()

            for line in lines:
                if len(line) > 1:
                    if not in_song_list:
                        in_song_list = (line[0:4] == '$$$$')
                    else:
                        if line[0] != ' ':
                            # Assume text in column 1 starts a song entry
                            song_info.dump(writer)

                            # Title is anything from start of line until "(", "-",
                            # or date
                            ix = line.find('(')
                            if ix > 0:
                                # has a book name or composer
                                song_info.set_title( line[0:ix] )
                                iy = line.find(')')
                                if iy > 0:
                                    song_info.set_book( line[ix+1:iy] )
                            else:
                                ix = line.find('-')
                                if ix > 0:
                                    song_info.set_title( line[0:ix] )
                                else:
                                    # For now, take entire line as title
                                    # For extra credit, stop if you hit a date
                                    song_info.set_title( line )

                            # get dates on title line
                            song_info.add_dates( get_dates( line ) )

                        else:
                            # Assume a continuation line; most have dates
                            song_info.add_dates( get_dates( line ) )

                        song_info.add_raw_line( line )

            # Dump any open song
            song_info.dump(writer)

#==============================================================================
if __name__ == "__main__":    
    main()
