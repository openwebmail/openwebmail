#!/bin/bash

# Dimitris Michelinakis - v0.3 - 2/10/2004
#
# This script generates Cool3D icons with multi language text
# based on mkcool3d_en.sh by Andrea Partinico
#
# requirements:
#               1) Netpbm version 10.18 or newer which includes:
#               giftopnm, pbmtext, pnmpaste, ppmcolormask,
#               pnmcomp, pnminvert, pnmtogif
#
#               2) Optional custom font in BDF or PBM format to support
#               extra language characters/charsets.
#
#               3) OWM version 2.41 or newer
#
# usage:
#        1) If you need to generate characters for a language which
#        is not defined within the iso-8859-1 charset, then you need
#        to find or create a font file. Please read the pbmtext man page.
#
#        2) Move this script in your 'iconsets' directory along with
#        any custom fonts you want to use.
#
#        3) Execute from the iconsets directory with the required parameters.
#
##############################################################################
# Commandline options
#
# mkcool3d.sh <short lang name> <long lang name> <path to lang dir> [font]
#
# examples:
# mkcool3d.sh en English /var/www/cgi-bin/openwebmail/etc/lang
# mkcool3d.sh el Hellenic /var/www/cgi-bin/openwebmail/etc/lang elfont.bdf
##############################################################################
#
# Notes / Problems & Solutions
#
# 1) Some fonts sizes may generate a 'g' character thats missing a one
# or two pixels from below. You may need to modify the parameter "-bottom"
# of the giftopnm command.
#
# 2) The "Information" button has no text because no language translation
# exists in the lang/ files.
#
# 3) The language text can be fairly long, thus some buttons appear quite
# long and can cause the page to scroll at resolutions 1024x768 or less. The
# solution is to use two-line text but this hasn't been implemented yet.
#
# 4) If you are getting errors while generating the icons, its probably
# because you have an old netpbm version. You should upgdate to at least
# version 10.18. This script has been tested under Fedora Core 1 with 10.19-7.
#
# 5) If you need to generate your own BDF font file, then the easiest way
# is to load a temporary XFS daemon (as a user, no need for root) and
# by using the /usr/X11R6/lib/X11/fs/config as a base config file, remove
# the 'no-listen' option and run with "xfs -config customconfig". Finaly,
# you can use fstobdf with the -server 127.0.0.1:<port> and -fn as
# parameters to get the fonts you need.
#
##############################################################################


##############################################################################
# Configuration options - defined via commandline
##############################################################################

# Short name of language
LANGSHORT=$1

# Long name of language
LANGLONG=$2

# OWM language directory (no ending forward slash)
SOURCE=$3

# Custom font
if [ -n "$4" ]; then
	FONT=$4
fi

# Temporary directory
ROOT=/tmp

# Destination dir of icons
DEST=Cool3D.$LANGLONG


##############################################################################
# START OF SCRIPT - no need to modify anything from here
##############################################################################

# function that do the work
# usage: cool3dicon "text to add" starticon.gif > desticon.gif
cool3dicon() {
	TEXT=$1
	STARTICON=$2

	BLANKICON=Cool3D/blank.gif
	GBASEFILE=$ROOT/base
	GCUTFILE=$ROOT/cut
	GTEXTFILE=$ROOT/text
	GFINALFILE=$ROOT/final
	GALPHAFILE=$ROOT/alpha

	# find transparent color (must be imposed because in blank.gif transparent color is not defined)
	#TRCOLOR=`giftopnm -verbose $BLANKICON 2>&1 | head -n 8|grep transparent|cut -s -d " " -f 5`
	# | head -n 1 | cut -s -d " " -f 5 | cut -s -d ":" -f 2 | tr -d /`
	TRCOLOR="000080"

	# make text
	if [ -n "$FONT" ]; then
		pbmtext -nomargins -font $FONT "$TEXT" >$GTEXTFILE
	else
		pbmtext -nomargins "$TEXT" >$GTEXTFILE
	fi

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
	TRCOL=`giftopnm -verbose $STARTICON 2>&1 | head -n 10|grep transparent|cut -s -d " " -f 5`
	# | head -n 1 | cut -s -d " " -f 5 | cut -s -d ":" -f 2 | tr -d /`
	giftopnm $STARTICON | pnmcut -left 3 -top 4 -right 21 -bottom 21 >$GCUTFILE
	XOFFSET=`expr $LENGHT - 18`
	XOFFSET=`expr $XOFFSET / 2`
	ppmcolormask $TRCOL $GCUTFILE >$GALPHAFILE
	pnmcomp -xoff=$XOFFSET -yoff=4 -alpha=$GALPHAFILE $GCUTFILE $GBASEFILE $GFINALFILE
	cp $GFINALFILE $GBASEFILE

	# overlay text
	pnminvert $GTEXTFILE >$GALPHAFILE
	pnmcomp -xoff=5 -yoff=25 -alpha=$GALPHAFILE $GTEXTFILE $GBASEFILE $GFINALFILE

	# convert to gif, make transparence, save, clean and exit
	ppmtogif -transparent \#$TRCOLOR $GFINALFILE
	rm -rf $GBASEFILE $GCUTFILE $GTEXTFILE $GFINALFILE $GALPHAFILE
}

# use default icon which are transparent
BASE=Default

# make dest dir from base
rm -rf ./$DEST
cp -a $BASE $DEST

# load language text
ADDRBOOK=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "addressbook@" |awk -F "'" '{ print $2 }'`
ADDUSER=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "add" |awk -F "'" '{ print $2 }'`
ADVSEARCH=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "advsearch" |awk -F "'" '{ print $2 }'`
BACKTOFOLDER=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "back " | awk -F "'" '{ print $2 }'`
CALENDAR=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "calendar" | awk -F "'" '{ print $2 }'`
CHPWD=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "changepwd" | awk -F "'" '{ print $2 }'`
CLEARADDRESS=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "clearadd" | awk -F "'" '{ print $2 }'`
CLEARST=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "clearstat" | awk -F "'" '{ print $2 }'`
COMPOSE=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "composenew" | awk -F "'" '{ print $2 }'`
DAYVIEW=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "dayview" | awk -F "'" '{ print $2 }'`
EDITDRAFT=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "editdraft" | awk -F "'" '{ print $2 }'`
EDITFROMS=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "editfroms" | awk -F "'" '{ print $2 }'`
EDITST=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "editstat" | awk -F "'" '{ print $2 }'`
EMPTYFOLDER=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "emptyfolder" | awk -F "'" '{ print $2 }'`
EXPORT=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "exportadd" | awk -F "'" '{ print $2 }'`
FILTERSETUP=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "filterbook" | awk -F "'" '{ print $2 }'`
FOLDER=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "folders " | awk -F "'" '{ print $2 }'`
FORWARDASATT=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "forwardasatt" | awk -F "'" '{ print $2 }'`
FORWARDASORIG=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "forwardasorig" | awk -F "'" '{ print $2 }'`
FORWARD=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "forward" | awk -F "'" '{ print $2 }'`
HISTORY=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "viewhistory" | awk -F "'" '{ print $2 }'`
HOME=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "homedir" | awk -F "'" '{ print $2 }'`
IMPORT=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "import" | awk -F "'" '{ print $2 }'`
# no defined text for info button yet
INFO="i"
LEARNSPAM=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "learnspam" | awk -F "'" '{ print $2 }'`
LISTVIEW=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "listview" | awk -F "'" '{ print $2 }'`
LOGOUT=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "logout" | awk -F "'" '{ print $2 }'`
MONTHVIEW=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "monthview" | awk -F "'" '{ print $2 }'`
OWM=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "webmail" | awk -F "'" '{ print $2 }'`
POP3=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "retr_pop3s" | awk -F "'" '{ print $2 }'`
POP3SETUP=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "pop3book" | awk -F "'" '{ print $2 }'`
PREFS=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "preferences" | awk -F "'" '{ print $2 }'`
PRINT=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "printfriendly" | awk -F "'" '{ print $2 }'`
REFRESH=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "refresh" |tail -n 1 | awk -F "'" '{ print $2 }'`
REPLYALL=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "replyall" | awk -F "'" '{ print $2 }'`
REPLY=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "reply" | awk -F "'" '{ print $2 }'`
SSHTERM=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "sshterm" | awk -F "'" '{ print $2 }'`
THUMBNAIL=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "showthumbnail" | awk -F "'" '{ print $2 }'`
TOTRASH=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "totrash" | awk -F "'" '{ print $2 }'`
TRASH=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "emptytrash" | awk -F "'" '{ print $2 }'`
VDUSERS=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "vdomain_usermgr" | awk -F "'" '{ print $2 }'`
WEBDISK=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "webdisk " | awk -F "'" '{ print $2 }'`
WEEKVIEW=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "weekview" | awk -F "'" '{ print $2 }'`
YEARVIEW=`awk -F "=>" '{ print $1 "@" $2 }' $SOURCE/$LANGSHORT |grep -w "yearview" | awk -F "'" '{ print $2 }'`

# call cool3dicon function with required parameters
cool3dicon "$ADDRBOOK" $BASE/addrbook.gif > $DEST/addrbook.gif
cool3dicon "$ADDUSER" $BASE/adduser.gif > $DEST/adduser.gif
cool3dicon "$ADVSEARCH" $BASE/advsearch.gif > $DEST/advsearch.gif
cool3dicon "$BACKTOFOLDER" $BASE/backtofolder.gif > $DEST/backtofolder.gif
cool3dicon "$CALENDAR" $BASE/calendar.gif > $DEST/calendar.gif
cool3dicon "$CHPWD" $BASE/chpwd.gif > $DEST/chpwd.gif
cool3dicon "$CLEARADDRESS" $BASE/clearaddress.gif > $DEST/clearaddress.gif
cool3dicon "$CLEARST" $BASE/clearst.gif > $DEST/clearst.gif
cool3dicon "$COMPOSE" $BASE/compose.gif > $DEST/compose.gif
cool3dicon "$DAYVIEW" $BASE/dayview.gif > $DEST/dayview.gif
cool3dicon "$EDITDRAFT" $BASE/editdraft.gif > $DEST/editdraft.gif
cool3dicon "$EDITFROMS" $BASE/editfroms.gif > $DEST/editfroms.gif
cool3dicon "$EDITST" $BASE/editst.gif > $DEST/editst.gif
cool3dicon "$EMPTYFOLDER" $BASE/emptyfolder.gif > $DEST/emptyfolder.gif
cool3dicon "$EXPORT" $BASE/export.gif > $DEST/export.gif
cool3dicon "$FILTERSETUP" $BASE/filtersetup.gif > $DEST/filtersetup.gif
cool3dicon "$FOLDER" $BASE/folder.gif > $DEST/folder.gif
cool3dicon "$FORWARDASATT" $BASE/forwardasatt.gif > $DEST/forwardasatt.gif
cool3dicon "$FORWARDASORIG" $BASE/forwardasorig.gif > $DEST/forwardasorig.gif
cool3dicon "$FORWARD" $BASE/forward.gif > $DEST/forward.gif
cool3dicon "$HISTORY" $BASE/history.gif > $DEST/history.gif
cool3dicon "$HOME" $BASE/home.gif > $DEST/home.gif
cool3dicon "$IMPORT" $BASE/import.gif > $DEST/import.gif
cool3dicon "$INFO" $BASE/info.gif > $DEST/info.gif
cool3dicon "$LEARNSPAM" $BASE/learnspam.gif > $DEST/learnspam.gif
cool3dicon "$LISTVIEW" $BASE/listview.gif > $DEST/listview.gif
cool3dicon "$LOGOUT" $BASE/logout.gif > $DEST/logout.gif
cool3dicon "$MONTHVIEW" $BASE/monthview.gif > $DEST/monthview.gif
cool3dicon "$OWM" $BASE/owm.gif > $DEST/owm.gif
cool3dicon "$POP3" $BASE/pop3.gif > $DEST/pop3.gif
cool3dicon "$POP3SETUP" $BASE/pop3setup.gif > $DEST/pop3setup.gif
cool3dicon "$PREFS" $BASE/prefs.gif > $DEST/prefs.gif
cool3dicon "$PRINT" $BASE/print.gif > $DEST/print.gif
cool3dicon "$REFRESH" $BASE/refresh.gif > $DEST/refresh.gif
cool3dicon "$REPLYALL" $BASE/replyall.gif > $DEST/replyall.gif
cool3dicon "$REPLY" $BASE/reply.gif > $DEST/reply.gif
cool3dicon "$SSHTERM" $BASE/sshterm.gif > $DEST/sshterm.gif
cool3dicon "$THUMBNAIL" $BASE/thumbnail.gif > $DEST/thumbnail.gif
cool3dicon "$TOTRASH" $BASE/totrash.gif > $DEST/totrash.gif
cool3dicon "$TRASH" $BASE/trash.gif > $DEST/trash.gif
cool3dicon "$VDUSERS" $BASE/vdusers.gif > $DEST/vdusers.gif
cool3dicon "$WEBDISK" $BASE/webdisk.gif > $DEST/webdisk.gif
cool3dicon "$WEEKVIEW" $BASE/weekview.gif > $DEST/weekview.gif
cool3dicon "$YEARVIEW" $BASE/yearview.gif > $DEST/yearview.gif
