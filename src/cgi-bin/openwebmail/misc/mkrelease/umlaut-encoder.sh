#!/bin/bash
#
# Script for transcoding german umlauts to HTML encodings
#
# author: Martin Bronk (Martin AT Bronk.de)

template_files=`ls *\.template`

for file in ${template_files}; do
  cat ${file} | \
   sed s/"ä"/"\&auml;"/g | \
   sed s/"Ä"/"\&Auml;"/g | \
   sed s/"ö"/"\&ouml;"/g | \
   sed s/"Ö"/"\&Ouml;"/g | \
   sed s/"ü"/"\&uuml;"/g | \
   sed s/"Ü"/"\&Uuml;"/g | \
   sed s/"ß"/"\&szlig;"/g  \
   > ${file}.tmp
  mv ${file}.tmp ${file}
  echo "${file} encoded."
done

