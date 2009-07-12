<!--
=======================================================================
$Id: common.mrc.in.dist,v 1.22 2003/07/16 00:49:58 ehood Exp $

MHonArc resource file for mharc mail archives

Description:
This is the main resource file for the mail archives.
it contains all the common formatting characteristics
used across archives.  Archive specific settings can
be set via command-line options the bin/web-archive
program.

=======================================================================
-->




<!--
=======================================================================
Custom Variable Defintions
=======================================================================

The following variables defined here for OpenWebMail since we don't use
the normal web-archive of mharc program that usually defines these.
-->

<DefineVar chop>
ALL-LISTS-URL
/archive/html/index.htm
</DefineVar>

<DefineVar chop>
PERIOD-NEXT
$ENV(PERIOD-NEXT)$
</DefineVar>

<DefineVar chop>
PERIOD-PREV
$ENV(PERIOD-PREV)$
</DefineVar>

<DefineVar chop>
LIST-NAME
$ENV(LIST-NAME)$
</DefineVar>

<DefineVar chop>
LIST-TITLE
$LIST-NAME$ Mailing List
</DefineVar>

<DefineVar chop>
SEARCH-CGI
/archive/search.pl
</DefineVar>

<DefineVar chop>
POST-CGI
/archive/tools/post.pl
</DefineVar>

<DefineVar chop>
NMZ-CGI
/archive/search/index.pl
</DefineVar>














<!-- ================================================================== -->
<!--  Custom Text Variables                                             -->
<!-- ================================================================== -->

<!-- Variable for defining any <meta http-equiv> tags. -->
<DefineVar chop>
HTTP-EQUIV
</DefineVar>

<DefineVar chop>
PREV-PERIOD-LABEL
Prev&nbsp;Period
</DefineVar>

<DefineVar chop>
NEXT-PERIOD-LABEL
Next&nbsp;Period
</DefineVar>

<DefineVar chop>
ADV-SEARCH-LABEL
Advanced
</DefineVar>

<DefineVar chop>
THREAD-IDX-LABEL
Sort&nbsp;By&nbsp;Thread
</DefineVar>

<DefineVar chop>
DATE-IDX-LABEL
Sort&nbsp;By&nbsp;Date
</DefineVar>

<DefineVar chop>
TOP-LINK-LABEL
$LIST-NAME$&nbsp;Index
</DefineVar>

<DefineVar chop>
ALL-LISTS-LABEL
All&nbsp;Lists
</DefineVar>

<DefineVar chop>
PREV-MSG-BUTTON-LABEL
prev
</DefineVar>

<DefineVar chop>
NEXT-MSG-BUTTON-LABEL
next
</DefineVar>

<DefineVar chop>
DATE-IDX-BUTTON-LABEL
Date
</DefineVar>

<DefineVar chop>
THREAD-IDX-BUTTON-LABEL
Thread
</DefineVar>

<DefineVar chop>
ORIGINAL-MSG-LINK-LABEL
Original
</DefineVar>

<DefineVar chop>
PREV-IN-THREAD-LABEL
Prev&nbsp;in&nbsp;Thread
</DefineVar>

<DefineVar chop>
NEXT-IN-THREAD-LABEL
Next&nbsp;in&nbsp;Thread
</DefineVar>

<DefineVar chop>
CURRENT-THREAD-LABEL
Current&nbsp;Thread
</DefineVar>

<DefineVar chop>
PREV-BY-DATE-LABEL
Previous&nbsp;by&nbsp;Date
</DefineVar>

<DefineVar chop>
NEXT-BY-DATE-LABEL
Next&nbsp;by&nbsp;Date
</DefineVar>

<DefineVar chop>
PREV-BY-THREAD-LABEL
Previous&nbsp;by&nbsp;Thread
</DefineVar>

<DefineVar chop>
NEXT-BY-THREAD-LABEL
Next&nbsp;by&nbsp;Thread
</DefineVar>

<DefineVar chop>
INDEXES-LABEL
Indexes
</DefineVar>




















<!-- ================================================================== -->
<!--  Links and Buttons                                                 -->
<!-- ================================================================== -->

<DefineVar chop>
STYLESHEET-LINK
<link rel="stylesheet" type="text/css" href="/archive/css/owm.css">
</DefineVar>

<DefineVar chop>
PREV-PERIOD-LINK
&lt;&nbsp;<a href="../$PERIOD-PREV$" class="navPrevNext">$PREV-PERIOD-LABEL$</a>&nbsp;&nbsp;
</DefineVar>

<DefineVar chop>
NEXT-PERIOD-LINK
&nbsp;&nbsp;<a href="../$PERIOD-NEXT$" class="navPrevNext">$NEXT-PERIOD-LABEL$</a>&nbsp;&gt;
</DefineVar>

<DefineVar chop>
TPREV-PERIOD-LINK
&lt;&nbsp;<a href="../$PERIOD-PREV$/threads.html" class="navPrevNext">$PREV-PERIOD-LABEL$</a>&nbsp;&nbsp;
</DefineVar>

<DefineVar chop>
TNEXT-PERIOD-LINK
&nbsp;&nbsp;<a href="../$PERIOD-NEXT$/threads.html" class="navPrevNext">$NEXT-PERIOD-LABEL$</a>&nbsp;&gt;
</DefineVar>

<DefineVar chop>
PREV-PERIOD-BUTTON
$PREV-PERIOD-LINK$
</DefineVar>

<DefineVar chop>
NEXT-PERIOD-BUTTON
$NEXT-PERIOD-LINK$
</DefineVar>

<DefineVar chop>
TPREV-PERIOD-BUTTON
$TPREV-PERIOD-LINK$
</DefineVar>

<DefineVar chop>
TNEXT-PERIOD-BUTTON
$TNEXT-PERIOD-LINK$
</DefineVar>

<DefineVar chop>
THREAD-IDX-LINK
[<b><a href="$TIDXFNAME$" class="navLinks">$THREAD-IDX-LABEL$</a></b>]
</DefineVar>

<DefineVar chop>
DATE-IDX-LINK
[<b><a href="$IDXFNAME$" class="navLinks">$DATE-IDX-LABEL$</a></b>]
</DefineVar>

<DefineVar>
SEARCH-FORM
<form method="get" action="$NMZ-CGI$">
<nobr><input type="text" name="query" size="20"><input type="submit" name="submit" value="Search"><small>&nbsp;[<a href="$NMZ-CGI$"><font color="#000000">$ADV-SEARCH-LABEL$</font></a>]</small></nobr>
</form>
</DefineVar>

<DefineVar>
LOGO-LINK
<a href="http://openwebmail.acatysmoof.com"><img src="/images/openwebmail.gif" border="0" title="go to the OpenWebMail Project homepage"></a><br><br>
</DefineVar>

























<!-- ================================================================== -->
<!--	General Resources						-->
<!-- ================================================================== -->
<TITLE>
$LIST-NAME$ Index By Date
</TITLE>

<TTITLE>
$LIST-NAME$ Index By Thread
</TTITLE>

<SUBJECTSTRIPCODE>
s/^(?:\[owm-.*?\]|Re:?) ?//;
</SUBJECTSTRIPCODE>

<!-- We specify resource settings everytime, no need to save.  -->
<NoSaveResources>

<!-- the link does not go well here.  -->
<NoDoc>

<!-- mask email addresses from harvesters -->
<SPAMMODE>

<!-- don't mess up email or messageid or search links in message bodies. Posters responsibility. -->
<NOMODIFYBODYADDRESSES>

<!-- Register the custom linkify filter -->
<MIMEFILTERS>
text/html; linkify::filter; linkify.pl
</MIMEFILTERS>

<!-- Arguments to content filters.
     CAUTION: Verify options against security concerns and make
	      any changes accordingly.

     Summary of settings:
	. Inline images if no disposition provided.
	. Use content-type-based icons for attachments, see ICONS setting below.
	. Text/plain attachments should be saved to a separate file.
	  By default, MHonArc inlines all text/plain entities.
	. Italicize quoted text in messages.
	. Make sure line lengths in text messages do not exceed 80 characters.
	. Suppress output of HTML document title for HTML entities.
  -->
<MIMEArgs override>
m2h_external::filter;	inline useicon
m2h_text_plain::filter;	attachcheck quote maxwidth=80
m2h_text_html::filter;	notitle allownoncidurls
</MIMEArgs>

<!-- A little stricter MSGSEP.  Not important if CONLEN active.
     Try to be more strict than '^From ', but not too strict to deal
     with possible variations.
  -->
<MsgSep>
^From \S+.*\d+:\d+:\d+
</MsgSep>

<!-- Icons settings copied from documentation.  Works with
     Apache server.  Icons not used in index, but attachment
     filter is given useicon argument.  If Apache is not used,
     or the icon URLs are different, this resource needs to
     be changed or the useicon argument removed from
     m2h_external::filter.
  -->
<Icons>
application/*;[20x22]/icons/generic-text.gif
application/msword;[20x22]/icons/dot-doc.gif
application/postscript;[20x22]/icons/dot-ps.gif
application/rtf;[20x22]/icons/dot-doc.gif
application/x-csh;[20x22]/icons/dot-sh.gif
application/x-dvi;[20x22]/icons/generic-coding.gif
application/x-gtar;[20x22]/icons/dot-tar.gif
application/x-gzip;[20x22]/icons/dot-zip.gif
application/x-ksh;[20x22]/icons/dot-sh.gif
application/x-latex;[20x22]/icons/dot-tex.gif
application/octet-stream;[20x22]/icons/dot-exe.gif
application/x-patch;[20x22]/icons/generic-coding.gif
application/pdf;[20x22]/icons/dot-pdf.gif
application/x-script;[20x22]/icons/dot-sh.gif
application/x-sh;[20x22]/icons/dot-sh.gif
application/x-tar;[20x22]/icons/dot-tar.gif
application/x-tex;[20x22]/icons/dot-tex.gif
application/x-zip-compressed;[20x22]/icons/dot-zip.gif
application/zip;[20x22]/icons/dot-zip.gif
audio/*;[20x22]/icons/generic-audio.gif
chemical/*;[20x22]/icons/generic-text.gif
image/*;[20x22]/icons/dot-jpg.gif
message/external-body;[20x22]/icons/generic-text.gif
multipart/*;[20x22]/icons/generic-text.gif
text/*;[20x22]/icons/dot-txt.gif
video/*;[20x22]/icons/dot-mov.gif
*/*;[20x22]/icons/generic-text.gif
</Icons>





















<!-- ================================================================== -->
<!--	Main Index 							-->
<!-- ================================================================== -->

<!-- Set sorting order of main index pages: Reverse chronological.  -->
<Sort>
<Reverse>

<!-- Show dates in local time. -->
<UseLocalTime>

<!-- Make date index the default page for the archive. -->
<IdxFName>
index.html
</IdxFName>

<!-- Default date format to use for dates.  This can be overridden
     on a per resource variable instance.
  -->
<MsgLocalDateFmt>
%B %d, %Y
</MsgLocalDateFmt>

<IdxPgBegin>
<html>
<head>
$HTTP-EQUIV$
<title>$IDXTITLE$</title>
$STYLESHEET-LINK$
</head>
<body>
<table cellpadding="0" cellspacing="0" border="0" width="80%" align="center">
<tr>
  <td colspan="3" align="center">$LOGO-LINK$</td>
</tr>
<tr>
  <td colspan="3" align="center">
    <table cellpadding="0" cellspacing="0" border="0">
    <tr>
      <td class="idxTitle">$IDXTITLE$</td>
    </tr>
    </table>
  </td>
</tr>
<tr>
  <td colspan="3" align="center" class="navLinks"><nobr>
    [<a href="$TIDXFNAME$" class="navLinks">$THREAD-IDX-LABEL$</a>]&nbsp;
    [<a href="../" class="navLinks">$TOP-LINK-LABEL$</a>]&nbsp;
    [<a href="$ALL-LISTS-URL$" class="navLinks">$ALL-LISTS-LABEL$</a>]&nbsp;
    [<a href="http://openwebmail.acatysmoof.com/archive/mj_wwwusr.pl?func=lists-long" class="navLinks">Subscribe</a>]
  </nobr></td>
</tr>
</IdxPgBegin>

<ListBegin>
<tr>
  <td colspan="3" align="center">
    <table cellpadding="0" cellspacing="0" border="0" width="100%">
    <tr>
      <td width="10%" class="navPrevNext">$PREV-PERIOD-BUTTON$</td>
      <td width="2%">&nbsp;</td>
      <td width="12%" align="center" class="navNewTopic"><a href="javascript:void(0);" onClick="window.open('$POST-CGI$?list=$LIST-NAME$&newtopic=1','replywindow','height=450,width=700,status=yes,toolbar=no,menubar=no,location=no');" class="navNewTopic">New Topic</a></td>
      <td align="center">$SEARCH-FORM$</td>
      <td width="12%" align="center" class="navNewTopic"><a href="javascript:void(0);" onClick="window.open('$POST-CGI$?list=$LIST-NAME$&newtopic=1','replywindow','height=450,width=700,status=yes,toolbar=no,menubar=no,location=no');" class="navNewTopic">New Topic</a></td>
      <td width="2%">&nbsp;</td>
      <td align="right" width="10%" class="navPrevNext">$NEXT-PERIOD-BUTTON$</td>
    <tr>
    </table>
  </td>
</tr>
</table>
</ListBegin>

<!-- Date listing is done in day groups with the each day listed in bold
     and messages for that date listed under it.
  -->
<DayBegin>
<table cellpadding="0" cellspacing="10" border="0" width="80%" align="center">
<tr>
  <td class="byDate">
    <span class="byDateHeader">$MSGLOCALDATE$</span>
    <ul>
</DayBegin>

<DayEnd>
    </ul>
  </td>
</tr>
</table>
</DayEnd>

<LITemplate>
      <li class="byDate"><a $A_ATTR$ class="byDate">$SUBJECTNA$</a>, <i>$FROMNAME$</i>, <tt>$MSGLOCALDATE(CUR;%H:%M)$</tt></li>
</LITemplate>

<ListEnd>
<table cellpadding="0" cellspacing="0" border="0" width="80%" align="center">
<tr>
  <td colspan="3" align="center">
    <table cellpadding="0" cellspacing="0" border="0" width="100%">
    <tr>
      <td width="10%" class="navPrevNext">$PREV-PERIOD-BUTTON$</td>
      <td width="2%">&nbsp;</td>
      <td width="12%" align="center" class="navNewTopic"><a href="javascript:void(0);" onClick="window.open('$POST-CGI$?list=$LIST-NAME$&newtopic=1','replywindow','height=450,width=700,status=yes,toolbar=no,menubar=no,location=no');" class="navNewTopic">New Topic</a></td>
      <td align="center">&nbsp;</td>
      <td width="12%" align="center" class="navNewTopic"><a href="javascript:void(0);" onClick="window.open('$POST-CGI$?list=$LIST-NAME$&newtopic=1','replywindow','height=450,width=700,status=yes,toolbar=no,menubar=no,location=no');" class="navNewTopic">New Topic</a></td>
      <td width="2%">&nbsp;</td>
      <td align="right" width="10%" class="navPrevNext">$NEXT-PERIOD-BUTTON$</td>
    <tr>
    </table>
  </td>
</tr>
</table>
<br><br><br>
</ListEnd>























<!-- ================================================================== -->
<!--	Thread Index 							-->
<!-- ================================================================== -->

<!-- Reverse thread order. -->
<TReverse>

<!-- Show no indicator of subject-based thread detection since most
     people do not care.  NOTE: The blank line is important!  -->
<TSubjectBeg>

</TSubjectBeg>

<TIdxPgBegin>
<html>
<head>
$HTTP-EQUIV$
<title>$TIDXTITLE$</title>
$STYLESHEET-LINK$
</head>
<body>
<table cellpadding="0" cellspacing="0" border="0" width="80%" align="center">
<tr>
  <td colspan="3" align="center">$LOGO-LINK$</td>
</tr>
<tr>
  <td colspan="3" align="center">
    <table cellpadding="0" cellspacing="0" border="0">
    <tr>
      <td class="idxTitle">$TIDXTITLE$</td>
    </tr>
    </table>
  </td>
</tr>
<tr>
  <td colspan="3" align="center" class="navLinks"><nobr>
    [<a href="$IDXFNAME$" class="navLinks">$DATE-IDX-LABEL$</a>]&nbsp;
    [<a href="../" class="navLinks">$TOP-LINK-LABEL$</a>]&nbsp;
    [<a href="$ALL-LISTS-URL$" class="navLinks">$ALL-LISTS-LABEL$</a>]&nbsp;
    [<a href="http://openwebmail.acatysmoof.com/archive/mj_wwwusr.pl?func=lists-long" class="navLinks">Subscribe</a>]
  </nobr></td>
</tr>
</TIdxPgBegin>

<THead>
<tr>
  <td colspan="3" align="center">
    <table cellpadding="0" cellspacing="0" border="0" width="100%">
    <tr>
      <td width="10%" class="navPrevNext">$TPREV-PERIOD-BUTTON$</td>
      <td width="2%">&nbsp;</td>
      <td width="12%" align="center" class="navNewTopic"><a href="javascript:void(0);" onClick="window.open('$POST-CGI$?list=$LIST-NAME$&newtopic=1','replywindow','height=450,width=700,status=yes,toolbar=no,menubar=no,location=no');" class="navNewTopic">New Topic</a></td>
      <td align="center">$SEARCH-FORM$</td>
      <td width="12%" align="center" class="navNewTopic"><a href="javascript:void(0);" onClick="window.open('$POST-CGI$?list=$LIST-NAME$&newtopic=1','replywindow','height=450,width=700,status=yes,toolbar=no,menubar=no,location=no');" class="navNewTopic">New Topic</a></td>
      <td width="2%">&nbsp;</td>
      <td align="right" width="10%" class="navPrevNext">$TNEXT-PERIOD-BUTTON$</td>
    <tr>
    </table>
  </td>
</tr>
</table>
<br>

<table cellpadding="0" cellspacing="0" border="0" width="80%" align="center">
<tr>
  <td class="byThread">
    <ul class="byThread">
</THead>

<TTopBegin>
      <li class="byThread"><a $A_ATTR$ class="byThread">$SUBJECTNA$</a>, <i>$FROMNAME$</i>, <tt>$MSGLOCALDATE(CUR;%Y/%m/%d)$</tt>
</TTopBegin>

<TTopEnd>
      </li>
</TTopEnd>

<TSubListBeg>
        <ul class="byThreadSub">
</TSubListBeg>

<TSubListEnd>
        </ul>
</TSubListEnd>

<TLiTxt>
          <li><a $A_ATTR$ class="byThread">$SUBJECTNA$</a>, <i>$FROMNAME$</i>, <tt>$MSGLOCALDATE(CUR;%Y/%m/%d)$</tt>
</TLiTxt>

<TLiEnd>
          </li>
</TLiEnd>

<TSingleTxt>
      <li class="byThreadSingle"><a $A_ATTR$ class="byThread">$SUBJECTNA$</a>, <i>$FROMNAME$</i>, <tt>$MSGLOCALDATE(CUR;%Y/%m/%d)$</tt></li>
</TSingleTxt>

<TFoot>
    </ul>
  </td>
</tr>
</table>
<br>
<table cellpadding="0" cellspacing="0" border="0" width="80%" align="center">
<tr>
  <td colspan="3" align="center">
    <table cellpadding="0" cellspacing="0" border="0" width="100%">
    <tr>
      <td width="10%" class="navPrevNext">$TPREV-PERIOD-BUTTON$</td>
      <td width="2%">&nbsp;</td>
      <td width="12%" align="center" class="navNewTopic"><a href="javascript:void(0);" onClick="window.open('$POST-CGI$?list=$LIST-NAME$&newtopic=1','replywindow','height=450,width=700,status=yes,toolbar=no,menubar=no,location=no');" class="navNewTopic">New Topic</a></td>
      <td align="center">$SEARCH-FORM$</td>
      <td width="12%" align="center" class="navNewTopic"><a href="javascript:void(0);" onClick="window.open('$POST-CGI$?list=$LIST-NAME$&newtopic=1','replywindow','height=450,width=700,status=yes,toolbar=no,menubar=no,location=no');" class="navNewTopic">New Topic</a></td>
      <td width="2%">&nbsp;</td>
      <td align="right" width="10%" class="navPrevNext">$TNEXT-PERIOD-BUTTON$</td>
    <tr>
    </table>
  </td>
</tr>
</table>
<br><br>
</TFoot>





















<!-- ================================================================== -->
<!--	Message Pages							-->
<!-- ================================================================== -->

<ModTime>

<!-- We clip the subject title to 72 characters to prevent ugly pages
     due to very long subject lines.  The full subject text will still
     be shown in the formatted message header.  -->
<MsgPgBegin>
<html>
<head>
$HTTP-EQUIV$
<title>$SUBJECTNA:72$</title>
$STYLESHEET-LINK$
<link rev="made" href="mailto:$FROMNAME$">
<link rel="start" href="../">
<link rel="contents" href="$TIDXFNAME$#$MSGNUM$">
<link rel="index" href="$IDXFNAME$#$MSGNUM$">
<link rel="prev" href="$MSG(TPREV)$">
<link rel="next" href="$MSG(TNEXT)$">
</head>
<body>
<table cellpadding="0" cellspacing="0" border="0" width="80%" align="center">
<tr>
  <td colspan="3" align="center">$LOGO-LINK$</td>
</tr>
<tr>
  <td colspan="3" align="center">
    <table cellpadding="0" cellspacing="0" border="0">
    <tr>
      <td class="idxTitle">$LIST-TITLE$</td>
    </tr>
    </table>
  </td>
</tr>
<tr>
  <td colspan="3" align="center" class="navLinks"><nobr>
    [<a href="../" class="navLinks">$TOP-LINK-LABEL$</a>]&nbsp;
    [<a href="$ALL-LISTS-URL$" class="navLinks">$ALL-LISTS-LABEL$</a>]&nbsp;
    [<a href="http://openwebmail.acatysmoof.com/archive/mj_wwwusr.pl?func=lists-long" class="navLinks">Subscribe</a>]
  </nobr></td>
</tr>
</table>
<br>
</MsgPgBegin>

<!-- Top navigation. -->
<PrevButton chop>
&lt;&nbsp;<a href="$MSG(PREV)$" class="navPrevNext">$PREV-MSG-BUTTON-LABEL$</a>
</PrevButton>

<NextButton chop>
<a href="$MSG(NEXT)$" class="navPrevNext">$NEXT-MSG-BUTTON-LABEL$</a>&nbsp;&gt;
</NextButton>

<TPrevButton chop>
&lt;&nbsp;<a href="$MSG(TPREV)$" class="navPrevNext">$PREV-MSG-BUTTON-LABEL$</a>
</TPrevButton>

<TNextButton chop>
<a href="$MSG(TNEXT)$" class="navPrevNext">$NEXT-MSG-BUTTON-LABEL$</a>&nbsp;&gt;
</TNextButton>

<PrevButtonIA chop>
&lt;&nbsp;<span class="inactiveText">$PREV-MSG-BUTTON-LABEL$</span>
</PrevButtonIA>

<NextButtonIA chop>
<span class="inactiveText">$NEXT-MSG-BUTTON-LABEL$</span>&nbsp;&gt;
</NextButtonIA>

<TPrevButtonIA chop>
&lt;&nbsp;<span class="inactiveText">$PREV-MSG-BUTTON-LABEL$</span>
</TPrevButtonIA>

<TNextButtonIA chop>
<span class="inactiveText">$NEXT-MSG-BUTTON-LABEL$</span>&nbsp;&gt;
</TNextButtonIA>

<!-- The following variables represent nav buttons for use in TOPLINKS
     resource.  We use variables so TOPLINKS can be modified without
     redefining TOPLINKS.
  -->
<DefineVar chop>
TOP-DATE-NAV
<nobr>$BUTTON(PREV)$&nbsp;<strong>[<a href="$IDXFNAME$#$MSGNUM$" class="navPrevNext">$DATE-IDX-BUTTON-LABEL$</a>]</strong>&nbsp;$BUTTON(NEXT)$</nobr>
</DefineVar>

<DefineVar chop>
TOP-THREAD-NAV
<nobr>$BUTTON(TPREV)$&nbsp;<strong>[<a href="$TIDXFNAME$#$MSGNUM$" class="navPrevNext">$THREAD-IDX-BUTTON-LABEL$</a>]</strong>&nbsp;$BUTTON(TNEXT)$</nobr>
</DefineVar>

<DefineVar chop>
ORIGINAL-LINK
[<a href="$SEARCH-CGI$?msgid=$MSGID:U$&amp;original=1" class="msgLinks">$ORIGINAL-MSG-LINK-LABEL$ raw message</a>]
</DefineVar>

<DefineVar chop>
AUTHOR-LINK
<a href="$NMZ-CGI$?query=%2Bfrom%3A%22$FROMNAME:5:U$%22&amp;sort=date%3Aearly" class="msgLinks">search author</a>
</DefineVar>

<DefineVar chop>
SUBJECT-LINK
<a href="$NMZ-CGI$?query=%2Bsubject%3A%22$SUBJECTNA:U$%22&amp;sort=date%3Aearly" class="msgLinks">search subject</a>
</DefineVar>

<DefineVar chop>
PERMA-LINK
<a href="http://openwebmail.acatysmoof.com/archive/search.pl?msgid=$MSGID:U$" class="msgLinks">permalink</a>
</DefineVar>

<DefineVar chop>
REPLY-LINK
<a href="javascript:void(0);" onClick="window.open('$POST-CGI$?list=$LIST-NAME$&msgid=$MSGID:U$&msgsubject=$SUBJECTNA:U$','replywindow','height=450,width=600,status=yes,toolbar=no,menubar=no,location=no');" class="msgLinks">reply</a>
</DefineVar>

<TopLinks>
<table cellpadding="0" cellspacing="0" border="0" width="80%" align="center">
<tr>
  <td class="navPrevNext" width="10%">$TOP-DATE-NAV$</td>
  <td align="center">$SEARCH-FORM$</td>
  <td class="navPrevNext" width="10%" align="right">$TOP-THREAD-NAV$</td>
</tr>
</table>
<br>
</TopLinks>

<!-- Make sure subject heading is not too long.
     NOTE: We put the div tag for the message head here since the converted
	   message header cannot be modified after first conversion.
  -->
<SubjectHeader>
<table cellpadding="0" cellspacing="0" border="0" width="80%" align="center">
<tr>
  <td class="msgTopBox">
    <table cellpadding="0" cellspacing="0" border="0" width="100%">
    <tr>
      <td class="msgSubjectHeader"><nobr>$SUBJECTNA:72$</nobr></td>
      <td align="right" class="msgLinks" valign="top"><nobr>$AUTHOR-LINK$</nobr>&nbsp;::&nbsp;<nobr>$SUBJECT-LINK$</nobr>&nbsp;::&nbsp;<nobr>$PERMA-LINK$</nobr>&nbsp;::&nbsp;<nobr>$REPLY-LINK$</nobr></td>
    </tr>
    </table>
  </td>
</tr>
<tr><td class="msgSpacerBox">&nbsp;</td></tr>
</SubjectHeader>

<!-- Format message header in a table. -->
<FieldOrder>
to
from
date
</FieldOrder>

<Fieldsbeg>
<tr>
  <td class="msgFieldsBox">
    <table cellpadding="2" cellspacing="0" border="0">
</FieldsBeg>

<LabelBeg>
    <tr>
      <td align="right">
</LabelBeg>

<!-- Don't remove the space after the colon! It will break Namazu! -->
<LabelEnd>
: </td>
</LabelEnd>

<FldBeg>
      <td>
</FldBeg>

<FldEnd>
      </td>
    </tr>
</FldEnd>

<FieldsEnd>
    </table>
  </td>
</tr>
<tr>
  <td class="msgSpacerBox">&nbsp;</td>
</tr>
</FieldsEnd>

<LabelStyles>
-default-:strong
</LabelStyles>

<HeadBodySep>
<tr>
  <td class="msgBodyBox" width="80%">
    <table cellpadding="0" cellspacing="0" border="0" width="80%">
</HeadBodySep>

<!-- Disable explicit follow-up/references section and use $TSLICE$ instead.  -->
<NoFolRefs>

<!-- Set TSLICE resource to represent default $TSLICE$ behavior and
     mainly to set the maximum message page update ranges when messages
     are added to the archive.  I.e.  The before and after values
     should represent the largest before and after values we will use
     with $TSLICE$.
  -->
<TSlice>
10:10:1
</TSlice>

<!-- We set up slice formatting so current message in thread is not
     hyperlinked and "greyed out".  We could probably use CSS to
     do this, but <font> seems to still work with most popular
     graphical browsers.
  -->
<TSliceBeg>
<ul>
</TSliceBeg>

<TSliceTopBegin>
<li class="slice"><div class="sliceNotCur"><nobr><b>$SUBJECT$</b>, <i>$FROMNAME$ <small>$YYYYMMDD$</small></i></nobr></div></li>
</TSliceTopBegin>

<TSliceLiTxt>
<li class="slice"><div class="sliceNotCur"><nobr><b>$SUBJECT$</b>, <i>$FROMNAME$ <small>$YYYYMMDD$</small></i></nobr></div></li>
</TSliceLiTxt>

<TSliceSingleTxt>
<li class="slice"><div class="sliceNotCur"><nobr><b>$SUBJECT$</b>, <i>$FROMNAME$ <small>$YYYYMMDD$</small></i></nobr></div></li>
</TSliceSingleTxt>

<TSliceTopBeginCur>
<li class="slice"><div class="sliceCur"><nobr><strong>$SUBJECTNA$</strong>, <em>$FROMNAME$ <small>$YYYYMMDD$</small></em></nobr></div></li>
</TSliceTopBeginCur>

<TSliceLiTxtCur>
<li class="slice"><div class="sliceCur"><nobr><strong>$SUBJECTNA$</strong>, <em>$FROMNAME$ <small>$YYYYMMDD$</small></em></nobr></div></li>
</TSliceLiTxtCur>

<TSliceSingleTxtCur>
<li class="slice"><div class="sliceCur"><nobr><strong>$SUBJECTNA$</strong>, <em>$FROMNAME$ <small>$YYYYMMDD$</small></em></nobr></div></li>
</TSliceSingleTxtCur>

<TSliceEnd>
</ul>
</TSliceEnd>

<TPrevInButton chop>
&lt;&nbsp;<a href="$MSG(TPREVIN)$" class="tSlicePrev">$PREV-IN-THREAD-LABEL$</a>
</TPrevInButton>
<TNextInButton>
<a href="$MSG(TNEXTIN)$" class="tSliceNext">$NEXT-IN-THREAD-LABEL$</a>&nbsp;&gt;
</TNextInButton>

<TPrevInButtonIA chop>
<span class="inactiveText">&lt;&nbsp;$PREV-IN-THREAD-LABEL$</span>
</TPrevInButtonIA>
<TNextInButtonIA chop>
<span class="inactiveText">$NEXT-IN-THREAD-LABEL$&nbsp;&gt;</span>
</TNextInButtonIA>

<!-- The TSLICE-LISTING variable represents the thread slice listing
     at the bottom of message pages.  If threading is not needed for
     an archive, this variable can be redefined to the empty string
     in the archive specific resource file.
  -->
<DefineVar chop>
TSLICE-LISTING
<tr>
  <td class="tSliceBox">
    <table cellpadding="0" cellspacing="1" border="0" width="100%">
    <tr>
      <td align="left" width="10%" class="tSlicePrev">$BUTTON(TPREVIN)$</td>
      <td align="center" class="tSliceHeader">$CURRENT-THREAD-LABEL$</td>
      <td align="right" width="10%" class="tSliceNext">$BUTTON(TNEXTIN)$</td>
    </tr>
    <tr>
      <td colspan="3" class="tSlicesBox">
$TSLICE$
      </td>
    </tr>
    </table>
  </td>
</tr>
<tr><td class="msgSpacerBox">&nbsp;</td></tr>
</DefineVar>

<!-- Modify end of message body to include thread slice.  We also
     include convenient next/prev-in-thread links since scanning
     slice can be inconvenient for simple thread reading.
  -->
<MsgBodyEnd>
  <center>
  <br>
  <iframe src="$POST-CGI$?list=$LIST-NAME$&msgid=$MSGID:U$&msgsubject=$SUBJECTNA:U$" name="replybox" frameborder="0" scrollbar="no" width="99%" height="450">
  <!-- content for non-supporting browsers -->
  <p><b>-- Reply iframe not supported by your browser --</b></p>
  </iframe>
  </center>
  </table>
  </td>
</tr>
<tr><td class="msgSpacerBox">&nbsp;</td></tr>
<tr><td class="msgSpacerBox">&nbsp;</td></tr>
<tr><td class="msgSpacerBox">&nbsp;</td></tr>
$TSLICE-LISTING$
</MsgBodyEnd>

<!-- The following variable represents the index links for use in BOTLINKS.
     We use a variable so archives that disable an index, or add one,
     can just change this variable instead of redefining BOTLINKS.
  -->
<DefineVar chop>
BOTTOM-IDX-LINKS
[<a href="$IDXFNAME$#$MSGNUM$"><strong>$DATE-IDX-BUTTON-LABEL$</strong></a>]
[<a href="$TIDXFNAME$#$MSGNUM$"><strong>$THREAD-IDX-BUTTON-LABEL$</strong></a>]&nbsp;
</DefineVar>

<!-- Use a table to format bottom links -->
<PrevLink chop>
    <tr>
      <td align="right" width="10%">$PREV-BY-DATE-LABEL$:&nbsp;</td>
      <td><strong><a href="$MSG(PREV)$">$SUBJECT(PREV)$</a></strong>, <em>$FROMNAME(PREV)$</em></td>
    </tr>
</PrevLink>

<NextLink chop>
    <tr>
      <td align="right" width="10%">$NEXT-BY-DATE-LABEL$:&nbsp;</td>
      <td><strong><a href="$MSG(NEXT)$">$SUBJECT(NEXT)$</a></strong>, <em>$FROMNAME(NEXT)$</em></td>
    </tr>
</NextLink>

<TPrevLink chop>
    <tr>
      <td align="right" width="10%">$PREV-BY-THREAD-LABEL$:&nbsp;</td>
      <td><strong><a href="$MSG(TPREV)$">$SUBJECT(TPREV)$</a></strong>, <em>$FROMNAME(TPREV)$</em></td>
    </tr>
</TPrevLink>

<TNextLink chop>
    <tr>
      <td align="right" width="10%">$NEXT-BY-THREAD-LABEL$:&nbsp;</td>
      <td><strong><a href="$MSG(TNEXT)$">$SUBJECT(TNEXT)$</a></strong>, <em>$FROMNAME(TNEXT)$</em></td>
    </tr>
</TNextLink>

<BotLinks>
<tr>
  <td class="BotLinksBox">
    <table cellpadding="0" cellspacing="0" border="0">
$LINK(PREV)$
$LINK(NEXT)$
$LINK(TPREV)$
$LINK(TNEXT)$
    <tr>
      <td align="right" width="10%">$INDEXES-LABEL$:&nbsp;</td>
      <td>$BOTTOM-IDX-LINKS$[<a href="../"><strong>$TOP-LINK-LABEL$</strong></a>]&nbsp;[<a href="$ALL-LISTS-URL$"><strong>$ALL-LISTS-LABEL$</strong></a>]&nbsp;[<a href="http://openwebmail.acatysmoof.com/archive/mj_wwwusr.pl?func=lists-long"><strong>Subscribe</strong></a>]</td>
    </tr>
    </table>
  </td>
</tr>
</table>
</BotLinks>



