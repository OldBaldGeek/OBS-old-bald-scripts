#!/usr/bin/python
#
# SlideNumber.py: normalize names of files in a directory
# Python 3.8.5
#
# Written by John Hartman
# 22-Dec-2021 - add defaults to parameters
#
import sys
import os
import string
import re

#=============================================================================
#
# SlideNumber path spec.ext
#
def main():
   if (len(sys.argv) < 3):
      print( 'SlideNumber.py version 1.0' )
      print( 'Normalize the names of all files in a directory' )
      print( '' )
      print( 'Slidenumber.py path base ext newbase')
      print( '  where' )
      print( '  - path    specifies the directory' )
      print( '  - base    specifies the portion of name before the numbers' )
      print( '  - ext     specifies the extension to be processed (default "png")' )
      print( '  - newbase specifies the new name before the numbers (default "slide")' )
      return

   path = sys.argv[1]
   base = sys.argv[2]
   baseLen = len(base)

   ext = 'png';
   if (len(sys.argv) > 3):
      ext = sys.argv[3]

   newbase = 'slide';
   if (len(sys.argv) > 4):
      newbase = sys.argv[4]

   maxTail = 0
   ok = True
   files = []

   dirList = os.listdir(path)
   for fileName in dirList:
      index = fileName.rfind('.')
      if index < 0:
         print( 'Skipping %s which has no extension' % fileName )
      else:
         fileBase = fileName[:index]
         fileExt  = fileName[index+1:]
         if fileExt != ext:
            print( 'Skipping %s which has extension: %s' % (fileName, fileExt) )
         else:
            if fileBase.find(base) == 0:
               tail = fileBase[baseLen:]
               if not tail.isnumeric():
                  print( 'Error: %s has non-numeric tail: %s' % (fileName, tail) )
                  ok = False
               else:
                  val = len(tail)
                  files.append(tail)
                  # print( '%s has a tail of %i characters' % (fileName, val ) )
                  if val > maxTail:
                     maxTail = val
            else:
               print( 'Skipping %s which doesn\'t match %s' % (fileName, base) )

   if ok:
      print( 'Need %i digits for alignment' % maxTail )
      for tail in files:
         if True: # len(tail) < maxTail:
            oldName = '%s\\%s%s.%s' % (path, base, tail, ext)
            newName = '%s\\%s%s.%s' % (path, newbase, tail.zfill(maxTail), ext)
            print( 'Rename %s to %s' % (oldName, newName) )
            os.rename( oldName, newName )
         #else:
         #   print( 'OK as is  "%s + %s . %s"' % (base, tail, ext) )

if __name__ == "__main__":
   main()
