#!/bin/bash

# Script to add text to the icons in the Cool3D directory
# @2002 by Andrea Partinico - GLP license
# version 0.2 date 2002-07-25
# usage: translate at bottom, choose destination dir, call it from iconsets dir
# note: this version add text to the bottom of icons
# lang: en

# choose the destination dir of icons
DEST=Cool3D.English

#
# BEGIN OF SCRIPT
#

# function that do the work
# usage: cool3dicon "text to add" starticon.gif > desticon.gif
cool3dicon() {

	TEXT=$1
	STARTICON=$2

	BLANKICON=Cool3D/blank.gif
	GBASEFILE=/tmp/base
	GCUTFILE=/tmp/cut
	GTEXTFILE=/tmp/text
	GFINALFILE=/tmp/final
	GALPHAFILE=/tmp/alpha

	# find transparent color (must be imposed because in blank.gif transparent color is not defined)
#	TRCOLOR=`giftopnm -verbose $BLANKICON 2>&1 | head -n 1 | cut -s -d " " -f 5 | cut -s -d ":" -f 2 | tr -d /`
	TRCOLOR="000080"

	# make text
	pbmtext -space 1 "$TEXT" | pnmcut -left 14 -right -14 -top 10 -bottom -8 >$GTEXTFILE

	# calculate lenght, height
	LENGHT=`cat $GTEXTFILE | head -n 2 | tail -n 1 | cut -s -f 1 -d " "`
	LENGHT=`expr $LENGHT + 9`
	[ $LENGHT -lt 24 ] && LENGHT=24
	HEIGHT=39

	# make base icon
	giftopnm $BLANKICON | pnmcut -left 3 -top 4 -right 21 -bottom 22 | pnmscale -xsize=$LENGHT -ysize=$HEIGHT >$GBASEFILE

	# cut borders enlarge it & paste

	# left
	giftopnm $BLANKICON | pnmcut -left 0 -top 4 -right 2 -bottom 21 | pnmscale -xsize=3 -ysize=$HEIGHT >$GCUTFILE
	pnmpaste $GCUTFILE 0 0 $GBASEFILE>$GFINALFILE
	cp $GFINALFILE $GBASEFILE

	# right
	giftopnm $BLANKICON | pnmcut -left 22 -top 4 -right 24 -bottom 21 | pnmscale -xsize=3 -ysize=$HEIGHT >$GCUTFILE
	pnmpaste $GCUTFILE `expr $LENGHT - 3` 0 $GBASEFILE>$GFINALFILE
	cp $GFINALFILE $GBASEFILE

	# top
	giftopnm $BLANKICON | pnmcut -left 3 -top 0 -right 21 -bottom 3 | pnmscale -xsize=$LENGHT -ysize=4 >$GCUTFILE
	pnmpaste $GCUTFILE 0 0 $GBASEFILE>$GFINALFILE
	cp $GFINALFILE $GBASEFILE

	# bottom
	giftopnm $BLANKICON | pnmcut -left 3 -top 22 -right 21 -bottom 23 | pnmscale -xsize=$LENGHT -ysize=2 >$GCUTFILE
	pnmpaste $GCUTFILE 0 `expr $HEIGHT - 2` $GBASEFILE>$GFINALFILE
	cp $GFINALFILE $GBASEFILE

	# cut & paste corners

	# top left
	giftopnm $BLANKICON | pnmcut -left 0 -top 0 -right 2 -bottom 3 >$GCUTFILE
	pnmpaste $GCUTFILE 0 0 $GBASEFILE>$GFINALFILE
	cp $GFINALFILE $GBASEFILE

	# top right
	giftopnm $BLANKICON | pnmcut -left 22 -top 0 -right 24 -bottom 3 >$GCUTFILE
	pnmpaste $GCUTFILE `expr $LENGHT - 3` 0 $GBASEFILE>$GFINALFILE
	cp $GFINALFILE $GBASEFILE

	# bottom left
	giftopnm $BLANKICON | pnmcut -left 0 -top 22 -right 2 -bottom 23 >$GCUTFILE
	pnmpaste $GCUTFILE 0 `expr $HEIGHT - 2` $GBASEFILE>$GFINALFILE
	cp $GFINALFILE $GBASEFILE

	# bottom right
	giftopnm $BLANKICON | pnmcut -left 22 -top 22 -right 24 -bottom 23 >$GCUTFILE
	pnmpaste $GCUTFILE `expr $LENGHT - 3` `expr $HEIGHT - 2` $GBASEFILE>$GFINALFILE
	cp $GFINALFILE $GBASEFILE

	# cut & overlay image
	TRCOL=`giftopnm -verbose $STARTICON 2>&1 | head -n 1 | cut -s -d " " -f 5 | cut -s -d ":" -f 2 | tr -d /`
	giftopnm $STARTICON | pnmcut -left 3 -top 4 -right 21 -bottom 21 >$GCUTFILE
	XOFFSET=`expr $LENGHT - 18`
	XOFFSET=`expr $XOFFSET / 2`
	ppmcolormask \#$TRCOL $GCUTFILE | pnminvert >$GALPHAFILE
	pnmcomp -xoff=$XOFFSET -yoff=4 -alpha=$GALPHAFILE $GCUTFILE $GBASEFILE $GFINALFILE
	cp $GFINALFILE $GBASEFILE

	# overlay text
	pnmcomp -xoff=5 -yoff=25 -alpha=$GTEXTFILE $GTEXTFILE $GBASEFILE $GFINALFILE

	# convert to gif, make transparence, save, clean and exit
	ppmtogif $GFINALFILE | giftrans -t \#$TRCOLOR
	rm -f $GBASEFILE $GCUTFILE $GTEXTFILE $GFINALFILE $GALPHAFILE
}

# use default icon which are transparent
BASE=Default

# make dest dir from base
rm -rf $DEST
cp -a $BASE $DEST

##############################################################################
#                          Translate here                                    #
##############################################################################

cool3dicon "Addr Book"             $BASE/addrbook.gif > $DEST/addrbook.gif
cool3dicon "Adv Search"            $BASE/advsearch.gif > $DEST/advsearch.gif
cool3dicon "Back"                  $BASE/backtofolder.gif > $DEST/backtofolder.gif
cool3dicon "ToGB"                  $BASE/big52gb.gif > $DEST/big52gb.gif
cool3dicon "Calendar"              $BASE/calendar.gif > $DEST/calendar.gif
cool3dicon "Change Passwd"         $BASE/chpwd.gif > $DEST/chpwd.gif
cool3dicon "Clear Addr"            $BASE/clearaddress.gif > $DEST/clearaddress.gif
cool3dicon "New"                   $BASE/compose.gif > $DEST/compose.gif
cool3dicon "Day View"              $BASE/dayview.gif > $DEST/dayview.gif
cool3dicon "Edit Draft"            $BASE/editdraft.gif > $DEST/editdraft.gif
cool3dicon "Edit Froms"            $BASE/editfroms.gif > $DEST/editfroms.gif
cool3dicon "Export Addr"           $BASE/export.gif > $DEST/export.gif
cool3dicon "Filters"               $BASE/filtersetup.gif > $DEST/filtersetup.gif
cool3dicon "Folders"               $BASE/folder.gif > $DEST/folder.gif
cool3dicon "Forward"               $BASE/forwardasatt.gif > $DEST/forwardasatt.gif
cool3dicon "Fwd As Att"            $BASE/forward.gif > $DEST/forward.gif
cool3dicon "ToBig5"                $BASE/gb2big5.gif > $DEST/gb2big5.gif
cool3dicon "History"               $BASE/history.gif > $DEST/history.gif
cool3dicon "Import Addr"           $BASE/import.gif > $DEST/import.gif
cool3dicon "Info"                  $BASE/info.gif > $DEST/info.gif
cool3dicon "Logout"                $BASE/logout.gif > $DEST/logout.gif
cool3dicon "Month View"            $BASE/monthview.gif > $DEST/monthview.gif
cool3dicon "Web Mail"              $BASE/owm.gif > $DEST/owm.gif
cool3dicon "POP3"                  $BASE/pop3.gif > $DEST/pop3.gif
cool3dicon "POP3 Setup"            $BASE/pop3setup.gif > $DEST/pop3setup.gif
cool3dicon "Pref"                  $BASE/prefs.gif > $DEST/prefs.gif
cool3dicon "Print"                 $BASE/print.gif > $DEST/print.gif
cool3dicon "Refresh"               $BASE/refresh.gif > $DEST/refresh.gif
cool3dicon "Reply All"             $BASE/replyall.gif > $DEST/replyall.gif
cool3dicon "Reply"                 $BASE/reply.gif > $DEST/reply.gif
cool3dicon "To Trash"              $BASE/totrash.gif > $DEST/totrash.gif
cool3dicon "Empty Trash"           $BASE/trash.gif > $DEST/trash.gif
cool3dicon "Week View"             $BASE/weekview.gif > $DEST/weekview.gif
cool3dicon "Year View"             $BASE/yearview.gif > $DEST/yearview.gif
