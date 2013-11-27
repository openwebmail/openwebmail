
#                              The BSD License
#
#  Copyright (c) 2009-2013, The OpenWebMail Project
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#      * Redistributions of source code must retain the above copyright
#        notice, this list of conditions and the following disclaimer.
#      * Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#      * Neither the name of The OpenWebMail Project nor the
#        names of its contributors may be used to endorse or promote products
#        derived from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY The OpenWebMail Project ``AS IS'' AND ANY
#  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#  DISCLAIMED. IN NO EVENT SHALL The OpenWebMail Project BE LIABLE FOR ANY
#  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# mailparse.pl - mail parser with mime multiple decoding
#
# 1. it parse mail recursively.
# 2. it converts uuencoded blocks into base64-encoded attachments
#
# Note: These parse_... routine are designed for CGI program !
#       if (searchid eq "") {
#          # html display / content search mode
#          only attachment contenttype of text/... or n/a will be returned
#       } elsif (searchid eq "all") {
#          # used in message forwarding
#          all attachments are returned
#       } elsif (searchid eq specific-id ) {
#          # html requesting an attachment with specific nodeid
#          only return attachment with the id
#       }

package ow::mailparse;

use strict;
use warnings FATAL => 'all';

require "modules/tool.pl";
require "modules/mime.pl";

sub parse_header {
   # given a message header string and a message attributes hash
   # populate the hash with the field names and field bodies of the header lines
   my ($r_header, $r_message) = @_;

   # unfold the header lines, but not the last blank line
   my $header = ${$r_header};

   return if !defined $header || $header eq '';

   $header =~ s/\s+$//s;
   $header =~ s/\s*\n\s+/ /sg;

   my @headerlines = split(/\r*\n/, $header);

   return unless scalar @headerlines > 0;

   $r_message->{delimiter} = shift(@headerlines) if $headerlines[0] =~ m/^From /;

   foreach my $headerline (@headerlines) {
      last if $headerline !~ m/(.+?):\s*(.*)/;
      my ($fieldname, $fieldbody) = ($1, $2);
      next if $fieldname =~ m/^(?:received|body|attachment)$/i;
      $r_message->{lc($fieldname)} = $fieldbody;
   }

   if (exists $r_message->{'message-id'} && defined $r_message->{'message-id'} && length $r_message->{'message-id'} >= 128) {
      $r_message->{'message-id'} = '<' . substr($r_message->{'message-id'}, 1, 125) . '>';
   }

   return;
}

# Handle "message/rfc822,multipart,uuencode inside message/rfc822" encapsulation
sub parse_rfc822block {
   my ($r_block, $nodeid, $searchid) = @_;

   my @attachments = ();
   my $headerlen   = 0;
   my $header      = '';
   my $body        = '';
   my %msg         = ();

   $nodeid = 0 unless defined $nodeid;
   $headerlen = index(${$r_block}, "\n\n") + 1; # header end at 1st \n
   $header = substr(${$r_block}, 0, $headerlen);

   $msg{'content-type'} = 'N/A'; # assume msg as simple text

   parse_header(\$header, \%msg);

   # recover incomplete header for msgs resent from mailing list, tricky!
   if ($msg{'content-type'} eq 'N/A') {
      my $testdata = substr(${$r_block}, $headerlen + 1, 256);
      if (
            (
               $testdata =~ m/multi\-part message in MIME format/i
               && $testdata =~ m/\n--(\S*?)\n/s
            )
            || $testdata =~ m/\n--(\S*?)\nContent\-/is
            || $testdata =~ m/^--(\S*?)\nContent\-/is
         ) {
         $msg{'content-type'} = qq|multipart/mixed; boundary="$1"|;
      }
   }

   if ($msg{'content-type'} =~ /^multipart/i) {
      my $search_html_related_att = 0;

      my $subtype = $msg{'content-type'};
      $subtype =~ s/^multipart\/(.*?)[;\s].*$/$1/i;

      my $boundary = $msg{'content-type'};
      $boundary =~ s/.*?boundary\s?=\s?"([^"]+)".*$/$1/i or
         $boundary =~ s/.*?boundary\s?=\s?([^\s;]+);?\s?.*$/$1/i;
      $boundary = "--$boundary";

      my $boundarylen = length($boundary);

      my $bodystart = $headerlen + 1;

      my $boundarystart = index(${$r_block}, $boundary, $bodystart);

      if ($boundarystart >= $bodystart) {
          $body = substr(${$r_block}, $bodystart, $boundarystart - $bodystart);
      } else {
          $body = substr(${$r_block}, $bodystart);
          return ($header, $body, \@attachments);
      }


      my $i = 0;
      my $nextboundarystart = 0;
      my $attblockstart = $boundarystart + $boundarylen;

      while (substr(${$r_block}, $attblockstart, 2) ne '--') {
         # skip \n after boundary
         while (substr(${$r_block}, $attblockstart, 1) =~ m/[\n\r]/) {
            $attblockstart++;
         }

         $nextboundarystart = index(${$r_block}, "$boundary\n", $attblockstart);

         if ($nextboundarystart == $attblockstart) {
            # this attblock is empty?, skip it.
            $boundarystart=$nextboundarystart;
            $attblockstart=$boundarystart+$boundarylen;
            next;
         } elsif ($nextboundarystart < $attblockstart) {
            # last atblock?
            $nextboundarystart=index(${$r_block}, "$boundary--", $attblockstart);
         }
         if ($nextboundarystart > $attblockstart) {
            # normal attblock handling
            if (defined $searchid && ($searchid eq '' || $searchid eq 'all')) {
               my $r_attachments2=parse_attblock($r_block, $attblockstart, $nextboundarystart-$attblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
            } elsif (defined $searchid && ($searchid eq "$nodeid-$i" || $searchid =~ m/^$nodeid-$i-/)) {
               my $r_attachments2=parse_attblock($r_block, $attblockstart, $nextboundarystart-$attblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
               if (defined ${${$r_attachments2}[0]}{'content-type'} &&
                   ${${$r_attachments2}[0]}{'content-type'} =~ /^text\/html/i ) {
                  $search_html_related_att=1;	# to gather inlined attachment info for this html
               } else {
                  last;	# attblock after this is not the one to look for...
               }
            } elsif ($search_html_related_att) {
               if (defined $searchid && $searchid =~ m/^$nodeid-/) {
                  # an att is html related if it has same parent as html
                  my $r_attachments2=parse_attblock($r_block, $attblockstart, $nextboundarystart-$attblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
                  push(@attachments, @{$r_attachments2});
               } else {
                  last;	# attblock after this is not related to previous html
               }
            } # else : skip the att
            $boundarystart=$nextboundarystart;
            $attblockstart=$boundarystart+$boundarylen;
         } else {
            # abnormal attblock, last one?
            if (
                  defined $searchid
                  && (
                        $searchid eq ''
                        || $searchid eq 'all'
                        || $searchid eq "$nodeid-$i"
                        || $searchid =~ m/^$nodeid-$i-/
                     )
               ) {
               my $left=length(${$r_block})-$attblockstart;
               if ($left>0) {
                  my $r_attachments2=parse_attblock($r_block, $attblockstart, $left ,$subtype, $boundary, "$nodeid-$i", $searchid);
                  push(@attachments, @{$r_attachments2});
               }
            }
            last;
         }

         $i++;
      }
      return($header, $body, \@attachments);

   } elsif ($msg{'content-type'} =~ m/^message\/partial/i) {
      if (defined $searchid && ($searchid eq '' || $searchid eq 'all' || $searchid =~ m/^$nodeid/)) {
         my $partialbody=substr(${$r_block}, $headerlen+1);
         my ($partialid, $partialnumber, $partialtotal);
         $partialid=$1 if ($msg{'content-type'} =~ /;\s*id="(.+?)";?/i);
         $partialnumber=$1 if ($msg{'content-type'} =~ /;\s*number="?(.+?)"?;?/i);
         $partialtotal=$1 if ($msg{'content-type'} =~ /;\s*total="?(.+?)"?;?/i);
         my $filename;
         if ($partialtotal) {
            $filename="Partial-$partialnumber.$partialtotal.msg";
         } else {
            $filename="Partial-$partialnumber.msg";
         }
         push(@attachments, make_attachment("","", "Content-Type: $msg{'content-type'}",\$partialbody, length($partialbody),
   	    $msg{'content-transfer-encoding'},"message/partial", "attachment; filename=$filename",$partialid,$partialnumber,$msg{'content-description'}, $nodeid) );
      }
      $body=''; # zero the body since it becomes to message/partial
      return($header, $body, \@attachments);

   } elsif ($msg{'content-type'} =~ /^message\/external\-body/i ) {
      $body=substr(${$r_block}, $headerlen+1);
      my @extbodyattr=split(/;\s*/, $msg{'content-type'});
      shift (@extbodyattr);
      $body="This is an external body reference.\n\n".
            join(";\n", @extbodyattr)."\n\n".
            $body;
      return($header, $body, \@attachments);

   } elsif ($msg{'content-type'} =~ /^message/i ) {
      if (defined $searchid && ($searchid eq '' || $searchid eq 'all' || $searchid =~ m/^$nodeid/)) {
         $body=substr(${$r_block}, $headerlen+1);
         my ($header2, $body2, $r_attachments2)=parse_rfc822block(\$body, "$nodeid-0", $searchid);

         if (defined $searchid && ($searchid eq '' || $searchid eq 'all' || $searchid eq $nodeid)) {
            $header2 = ow::mime::decode_mimewords($header2);
            my $temphtml="$header2\n$body2";
            push(@attachments, make_attachment("","", "",\$temphtml, length($temphtml),
   		$msg{'content-transfer-encoding'},$msg{'content-type'}, "inline; filename=Unknown.msg","","",$msg{'content-description'}, $nodeid) );
         }

         push (@attachments, @{$r_attachments2});
      }

      $body=''; # zero the body since it becomes to header2, body2 and r_attachment2

      return($header, $body, \@attachments);
   } elsif ( $msg{'content-type'} =~ /^text/i || $msg{'content-type'} eq 'N/A' ) {
      $body=substr(${$r_block}, $headerlen+1);

      if (defined $searchid && ($searchid eq '' || $searchid eq 'all' || $searchid =~ m/^$nodeid-0/)) {
         if ($msg{'content-type'} =~ /^text\/plain/i || $msg{'content-type'} eq 'N/A' ) {
            # mime words inside a text/plain mail, not MIME compliant
            if ($body=~/=\?[^?]*\?[bq]\?[^?]+\?=/si ) {
               $body= ow::mime::decode_mimewords($body);
            }

            # uuencode blocks inside a text/plain mail, not MIME compliant
            if ( $body =~ /^begin [0-7][0-7][0-7][0-7]? [^\n\r]+\n.+?\nend\n/ims ) {
               my $r_attachments2 = [];
               ($body, $r_attachments2) = parse_uuencode_body($body, "$nodeid-0", $searchid);
               push(@attachments, @{$r_attachments2});
            }
         }
      }
      return($header, $body, \@attachments);

   } else {
      if (defined $searchid && ($searchid eq 'all' || $searchid =~ m/^$nodeid/)) {
         $body=substr(${$r_block}, $headerlen+1);
         if ($body=~/\S/ ) { # save att if contains chars other than \s
            push(@attachments, make_attachment("","", "",\$body,length($body),
					$msg{'content-transfer-encoding'},$msg{'content-type'}, "","","",$msg{'content-description'}, $nodeid) );
         }
      } else {
         # null searchid means CGI is in returning html code or in context searching
         # thus content of an non-text based attachment is no need to be returned
         my $bodylength = length(${$r_block})-($headerlen+1);
         my $fakeddata  = 'snipped...';
         push(@attachments, make_attachment(
                                              '',
                                              '',
                                              '',
                                              \$fakeddata,$bodylength,
                                              $msg{'content-transfer-encoding'},
                                              $msg{'content-type'},
                                              '',
                                              '',
                                              '',
                                              $msg{'content-description'},
                                              $nodeid
                                           )
             );
      }

      return($header, " ", \@attachments);
   }
}

# Handle "message/rfc822,multipart,uuencode inside multipart" encapsulation.
sub parse_attblock {
   my ($r_buff, $attblockstart, $attblocklen, $subtype, $boundary, $nodeid, $searchid)=@_;

   my @attachments=();
   my $attheaderlen=index(${$r_buff}, "\n\n", $attblockstart)+1 - $attblockstart;
   my $attheader=substr(${$r_buff}, $attblockstart, $attheaderlen);
   my $attcontentlength=$attblocklen-($attheaderlen+1);

   my %att = ();
   $att{'content-type'} = 'N/A'; # assume null content type

   parse_header(\$attheader, \%att);

   $att{'content-id'} =~ s/^\s*\<(.+)\>\s*$/$1/ if defined $att{'content-id'};

   if ($att{'content-type'} =~ m/^multipart/i) {
      my ($subtype, $boundary, $boundarylen);
      my ($boundarystart, $nextboundarystart, $subattblockstart);
      my $search_html_related_att=0;

      $subtype = $att{'content-type'};
      $subtype =~ s/^multipart\/(.*?)[;\s].*$/$1/i;

      $boundary = $att{'content-type'};
      $boundary =~ s/.*?boundary\s?=\s?"([^"]+)".*$/$1/i or
         $boundary =~ s/.*?boundary\s?=\s?([^\s;]+);?\s?.*$/$1/i;
      $boundary="--$boundary";
      $boundarylen=length($boundary);

      $boundarystart=index(${$r_buff}, $boundary, $attblockstart);
      if ($boundarystart < $attblockstart) {
	 # boundary not found in this multipart block
         # we handle this attblock as text/plain
         $att{'content-type'}=~s!^multipart/\w+!text/plain!i;
         if (
               defined $searchid
               && (
                     $searchid eq 'all'
                     || $searchid eq $nodeid
                     || ($searchid eq '' && $att{'content-type'} =~ m/^text/i)
                  )
            ) {
            my $attcontent=substr(${$r_buff}, $attblockstart+$attheaderlen+1, $attcontentlength);
            if ($attcontent=~/\S/ ) { # save att if contains chars other than \s
               push(@attachments, make_attachment($subtype,$boundary, $attheader,\$attcontent, $attcontentlength,
                                     @att{'content-transfer-encoding', 'content-type', 'content-disposition', 'content-id', 'content-location', 'content-description'},
                                     $nodeid) );
            }
         }
         return(\@attachments);	# return this non-boundaried multipart as text
      }

      my $i=0;
      $subattblockstart=$boundarystart+$boundarylen;
      while ( substr(${$r_buff}, $subattblockstart, 2) ne "--") {
         # skip \n after boundary
         while ( substr(${$r_buff}, $subattblockstart, 1) =~ /[\n\r]/ ) {
            $subattblockstart++;
         }

         $nextboundarystart=index(${$r_buff}, "$boundary\n", $subattblockstart);
         if ($nextboundarystart == $subattblockstart) {
            # this subattblock is empty?, skip it.
            $boundarystart=$nextboundarystart;
            $subattblockstart=$boundarystart+$boundarylen;
            next;
         } elsif ($nextboundarystart < $subattblockstart) {
            $nextboundarystart=index(${$r_buff}, "$boundary--", $subattblockstart);
         }

         if ($nextboundarystart > $subattblockstart) {
            # normal attblock
            if (defined $searchid && ($searchid eq '' || $searchid eq 'all')) {
               my $r_attachments2=parse_attblock($r_buff, $subattblockstart, $nextboundarystart-$subattblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
            } elsif (defined $searchid && ($searchid eq "$nodeid-$i" || $searchid=~/^$nodeid-$i-/)) {
               my $r_attachments2=parse_attblock($r_buff, $subattblockstart, $nextboundarystart-$subattblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
               if (defined ${${$r_attachments2}[0]}{'content-type'} &&
                   ${${$r_attachments2}[0]}{'content-type'} =~ /^text\/html/i ) {
                  $search_html_related_att=1;	# to gather inlined attachment info for this html
               } else {
                  last;	# attblock after this is not the one to look for...
               }
            } elsif ($search_html_related_att) {
               if (defined $searchid && $searchid =~ m/^$nodeid-/) {
                  # an att is html related if it has same parent as html
                  my $r_attachments2=parse_attblock($r_buff, $subattblockstart, $nextboundarystart-$subattblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
                  push(@attachments, @{$r_attachments2});
               } else {
                  last;	# attblock after this is not related to previous html
               }
            }
            $boundarystart=$nextboundarystart;
            $subattblockstart=$boundarystart+$boundarylen;
         } else {
            # abnormal attblock, last one?
            if (
                  defined $searchid
                  && (
                        $searchid eq ''
                        || $searchid eq 'all'
                        || $searchid eq "$nodeid-$i"
                        || $searchid =~ m/^$nodeid-$i-/
                     )
               ) {
               my $left=$attblocklen-$subattblockstart;
               if ($left>0) {
                  my $r_attachments2=parse_attblock($r_buff, $subattblockstart, $left ,$subtype, $boundary, "$nodeid-$i", $searchid);
                  push(@attachments, @{$r_attachments2});
               }
            }
            last;
         }

         $i++;
      }

   } elsif ($att{'content-type'} =~ /^message\/external\-body/i ) {
      if (defined $searchid && ($searchid eq '' || $searchid eq 'all' || $searchid =~ m/^$nodeid/)) {
         my $attcontent=substr(${$r_buff}, $attblockstart+$attheaderlen+1, $attcontentlength);
         my @extbodyattr=split(/;\s*/, $att{'content-type'}); shift (@extbodyattr);
         $attcontent="This is an external body reference.\n\n".
                     join(";\n", @extbodyattr)."\n\n".
                     $attcontent;
         push(@attachments, make_attachment($subtype,$boundary, $attheader,\$attcontent, $attcontentlength,
                               @att{'content-transfer-encoding', 'content-type', 'content-disposition', 'content-id', 'content-location', 'content-description'},
                               $nodeid) );
      }

   } elsif ($att{'content-type'} =~ /^message/i ) {
      if (defined $searchid && ($searchid eq '' || $searchid eq 'all' || $searchid =~ m/^$nodeid/)) {
         my $attcontent = substr(${$r_buff}, $attblockstart+$attheaderlen+1, $attcontentlength);
         $attcontent = ow::mime::decode_content($attcontent, $att{'content-transfer-encoding'});
         my ($header2, $body2, $r_attachments2)=parse_rfc822block(\$attcontent, "$nodeid-0", $searchid);
         if (defined $searchid && ($searchid eq '' || $searchid eq 'all' || $searchid eq $nodeid)) {
            $header2 = ow::mime::decode_mimewords($header2);
            my $temphtml="$header2\n$body2";
            push(@attachments, make_attachment($subtype,"", $attheader,\$temphtml, length($temphtml),
                                  @att{'content-transfer-encoding', 'content-type', 'content-disposition', 'content-id', 'content-location', 'content-description'},
                                  $nodeid) );
         }
         push (@attachments, @{$r_attachments2});
      }

   } elsif ($att{'content-type'} =~ /^text/i || $att{'content-type'} eq "N/A" ) {
      $att{'content-type'}="text/plain" if ($att{'content-type'} eq "N/A");
      if (defined $searchid && ($searchid eq '' || $searchid eq 'all' || $searchid =~ m/^$nodeid/)) {
         my $attcontent=substr(${$r_buff}, $attblockstart+$attheaderlen+1, $attcontentlength);
         if ($attcontent=~/\S/ ) { # save att if contains chars other than \s
            push(@attachments, make_attachment($subtype,$boundary, $attheader,\$attcontent, $attcontentlength,
                                  @att{'content-transfer-encoding', 'content-type', 'content-disposition', 'content-id', 'content-location', 'content-description'},
                                  $nodeid) );
         }
      }

   } elsif ($att{'content-type'}=~/^application\/ms\-tnef/i && ow::tool::findbin('tnef') ne '') {
      # content is required since caller need to parse tnef to get info of attachments in the tnef
      if (defined $searchid && ($searchid eq '' || $searchid eq 'all' || $searchid =~ m/^$nodeid/)) {
         my $attcontent=substr(${$r_buff}, $attblockstart+$attheaderlen+1, $attcontentlength);
         push(@attachments, make_attachment($subtype,$boundary, $attheader,\$attcontent, $attcontentlength,
                               @att{'content-transfer-encoding', 'content-type', 'content-disposition', 'content-id', 'content-location', 'content-description'},
                               $nodeid) );
      }

   } elsif ($att{'content-type'} =~ m/^application\/octet\-stream/i) {
      # Apple-Mail is known to encapsulate html in application/octet-stream instead of text/html
      # we should handle application/octet-streams that are html inline
      # bad things like script are stripped out later before display in the browser
      if (defined $searchid && ($searchid eq '' || $searchid eq 'all' || $searchid =~ m/^$nodeid/)) {
         my $attcontent = substr(${$r_buff}, $attblockstart + $attheaderlen + 1, $attcontentlength);
         my $testpiece = substr($attcontent, 0, ($attcontentlength > 500 ? 500 : $attcontentlength));
         my $knowntags = () = $testpiece =~ m/<(?:html|head|meta|style|script|title|body|p|br|font|table|tr|td|tbody|div)/igs;
         if ($knowntags >= 5) {
            # save att since it seems to be html (5 known tags in first 500 bytes)
            $att{'content-type'} = 'text/html';
            $att{'content-disposition'} = 'attachment; filename=Unknown.htm';
            push(@attachments, make_attachment($subtype,$boundary, $attheader,\$attcontent, $attcontentlength, @att{'content-transfer-encoding', 'content-type', 'content-disposition', 'content-id', 'content-location', 'content-description'}, $nodeid) );
         } elsif ($attcontent =~ m/\S/) { # not html - save att if it contains any non-whitespace chars
            push(@attachments, make_attachment($subtype,$boundary, $attheader,\$attcontent, $attcontentlength, @att{'content-transfer-encoding', 'content-type', 'content-disposition', 'content-id', 'content-location', 'content-description'}, $nodeid) );
         }
      }

   } else {
      if (defined $searchid && ($searchid eq 'all' || $searchid =~ m/^$nodeid/)) {
         my $attcontent=substr(${$r_buff}, $attblockstart+$attheaderlen+1, $attcontentlength);
         if ($attcontent=~/\S/) { # save att if it contains any non-whitespace chars
            push(@attachments, make_attachment($subtype,$boundary, $attheader,\$attcontent, $attcontentlength,
                                  @att{'content-transfer-encoding', 'content-type', 'content-disposition', 'content-id', 'content-location', 'content-description'},
                                  $nodeid) );
         }
      } else {
         # null searchid means CGI is in returning html code or in context searching
         # thus content of an non-text based attachment is no need to be returned
         my $fakeddata = "snipped...";
         push(@attachments, make_attachment($subtype,$boundary, $attheader,\$fakeddata,$attcontentlength,
                                  @att{'content-transfer-encoding', 'content-type', 'content-disposition', 'content-id', 'content-location', 'content-description'},
                                  $nodeid) );
      }

   }

   return \@attachments;
}

sub parse_uuencode_body {
   # convert uuencode block into base64 encoded atachment
   my ($body, $nodeid, $searchid) = @_;
   my @attachments=();
   my $i;

   # Handle uuencode blocks inside a text/plain mail
   $i=0;
   while ( $body=~/^begin ([0-7][0-7][0-7][0-7]?) ([^\n\r]+)\n(.+?)\nend\n/igms ) {
      if (defined $searchid && ($searchid eq '' || $searchid eq 'all' || $searchid eq "$nodeid-$i")) {
         my ($uumode, $uufilename, $uubody) = ($1, $2, $3);
         my $uutype;

         $uufilename=~/\.([\w\d]+)$/;
         $uutype=ow::tool::ext2contenttype($1);

         # convert and inline uuencode block into an base64 encoded attachment
         my $uuheader=qq|Content-Type: $uutype;\n|.
                      qq|\tname="$uufilename"\n|.
                      qq|Content-Transfer-Encoding: base64\n|.
                      qq|Content-Disposition: attachment;\n|.
                      qq|\tfilename="$uufilename"|;
         $uubody = ow::mime::encode_base64(ow::mime::uudecode($uubody));

         push( @attachments, make_attachment("","", $uuheader,\$uubody, length($uubody),
		"base64",$uutype, "attachment; filename=$uufilename","","","uuencoded attachment", "$nodeid-$i") );
      }
      $i++;
   }

   $body =~ s/^begin [0-7][0-7][0-7][0-7]? [^\n\r]+\n.+?\nend\n//igms;
   return ($body, \@attachments);
}

# subtype and boundary are inherit from parent attblocks,
# they are used to distingush if two attachments are within the same group
# note: the $r_attcontent is a reference to the contents of an attachment,
#       this routine will save this reference to attachment hash directly.
#       It means the caller must ensures the variable referenced by
#       $r_attcontent is kept untouched!
sub make_attachment {
   my ($subtype,$boundary, $attheader,$r_attcontent,$attcontentlength,
	$attencoding,$attcontenttype, $attdisposition,$attid,$attlocation,$attdescription,
        $nodeid)=@_;

   my ($attcharset, $attfilename, $attfilenamecharset);
   $attcharset=$1 if ($attcontenttype =~ /charset="?([^\s"';]*)"?\s?/i);
   ($attfilename, $attfilenamecharset) = get_filename_charset($attcontenttype, $attdisposition);

   # guess a better contenttype
   if ($attcontenttype =~ m!(video/mpg|application/octet\-stream)!i || $attcontenttype =~ m!^(N/A)$!) {
      my $oldtype = $1;
      my ($extension) = $attfilename =~ m/\.([\w\d]*)$/;
      my $newtype = ow::tool::ext2contenttype($extension);
      $attcontenttype =~ s!\Q$oldtype\E!$newtype!i;
   }

   # remove file=... from disposition
   $attdisposition =~ s/;.*// if defined $attdisposition;

   $attdescription = ow::mime::decode_mimewords($attdescription);

   return({	# return reference of hash
	subtype		=> $subtype,	# from parent block
	boundary	=> $boundary,	# from parent block
	header		=> $attheader,	# attheader is not decoded yet
	r_content 	=> $r_attcontent,
	'content-length'	=> $attcontentlength,
	'content-type' 		=> $attcontenttype || 'text/plain',
	'content-transfer-encoding'=> $attencoding,
	'content-id' 		=> $attid,
	'content-disposition' 	=> $attdisposition,
	'content-location' 	=> $attlocation,
	'content-description'	=> $attdescription,
	charset		=> $attcharset || '',
	filename 	=> $attfilename,
	filenamecharset => $attfilenamecharset||$attcharset,
	nodeid		=> $nodeid,
	referencecount	=> 0
   });
}

sub get_filename_charset {
   my ($contenttype, $disposition)=@_;
   my ($filename, $filenamecharset);

   $filename = $contenttype;
   if ($filename =~ s/^.+name\s?\*?[:=]\s?"?[\w\d\-]+''([^"]+)"?.*$/$1/i) {
      $filename = ow::tool::unescapeURL($filename);
   } elsif ($filename =~ s/^.+name\s?\*?[:=]\s?"?([^"]+)"?.*$/$1/i) {
      $filenamecharset = $1 if ($filename =~ m{=\?([^?]*)\?[bq]\?[^?]+\?=}xi);
      $filename = ow::mime::decode_mimewords($filename);
   } else {
      $filename = $disposition || '';
      if ($filename =~ s/^.+filename\s?\*?=\s?"?[\w\d\-]+''([^"]+)"?.*$/$1/i) {
         $filename = ow::tool::unescapeURL($filename);
      } elsif ($filename =~ s/^.+filename\s?\*?=\s?"?([^"]+)"?.*$/$1/i) {
         $filenamecharset = $1 if ($filename =~ m{=\?([^?]*)\?[bq]\?[^?]+\?=}xi);
         $filename = ow::mime::decode_mimewords($filename);
      } else {
         $filename = "Unknown.".ow::tool::contenttype2ext($contenttype);
      }
   }
   # the filename of achments should not contain path delimiter,
   # eg:/,\,: We replace it with !
   $filename = ow::tool::zh_dospath2fname($filename, '!');	# dos path
   $filename =~ s|[/:]|!|g;	# / unix patt, : mac path and dos drive

   return($filename, $filenamecharset);
}

sub get_smtprelays_connectfrom_byas_from_header {
   my $header=$_[0]; $header=~s/\s*\n\s+/ /gs;

   my @smtprelays=();
   my %connectfrom=();
   my %byas=();

   foreach (split(/\n/, $header)) {
      if (/^Received:(.+)$/i) {
         my $value=$1;

         # Received: from mail.rediffmailpro.com (mailpro4.rediffmailpro.com [203.199.83.214] (may be forged))
         #	by turtle.ee.ncku.edu.tw (8.12.3/8.12.3) with SMTP id hB4EbqTB066378
         #	for <tung@turtle.ee.ncku.edu.tw>; Thu, 4 Dec 2003 22:37:54 +0800 (CST)
         #	(envelope-from josephotumba@olatunde.net)
         # Received: (qmail 25340 invoked by uid 510); 4 Dec 2003 14:36:27 -0000

         # skip line of MTA self pipe
         # eg: Received: (qmail 25340 invoked by uid 510); 4 Dec 2003 14:36:27 -0000
         # eg: Received: (from tung@localhost) by .....
         next if ($value=~/^ \(.+?\)/);

         if ($value=~/ by\s+(\S+)/i) {
           $smtprelays[0]=$1 if (!defined $smtprelays[0]);	# the last relay on path
           $byas{$smtprelays[0]}=$1;
         }
         if ($value=~/ from\s+(\S+)\s+\((.+?) \(.*?\)\)/i ||
             $value=~/ from\s+(\S+)\s+\((.+?)\)/i ) {
            unshift(@smtprelays, $1); $connectfrom{$1}=$2;
         } elsif ($value=~/ from\s+(\S+)/i ||
                  $value=~/ \(from\s+(\S+)/i ) {
            unshift(@smtprelays, $1);
         }
      }
   }

   # count 1st fromhost as relay only if there are just 2 host on relaylist
   # since it means sender machine uses smtp to talk to our mail server directly
   shift(@smtprelays) if ($#smtprelays>1);

   return(\@smtprelays, \%connectfrom, \%byas);
}

1;
