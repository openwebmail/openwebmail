#!/usr/bin/perl -w
#
#This script searches through the Namazu field indexes and finds messages
#that match what the user is looking for. It returns a redirect to that
#message's html page. It's a poor mans search tool, but effective.
#

$|++;
use strict;
use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser carpout);

my ($param, $config);

# configuration
$config->{mboxarchiveroot} = "/usr/local/majordomo/lists/openwebmail.acatysmoof.com";
$config->{wwwarchiveroot} = "/home/alex/openwebmail.acatysmoof.com/archive";
$config->{msgids} = "$config->{wwwarchiveroot}/search/NMZ.field.message-id";
$config->{uris} = "$config->{wwwarchiveroot}/search/NMZ.field.uri";

$param->{msgid} = param('msgid') || undef;
$param->{orig} = param('original') || undef;

if (not defined $param->{msgid}) {
   print redirect('http://openwebmail.acatysmoof.com/archive/html');
} else {
   my $line = 1;
   my $docid = undef;

   open(MSGIDS, "<$config->{msgids}") or croak("Can't open messageID file $config->{msgids}\n");
   while (<MSGIDS>) { # seek this msgid
      chomp;
      if (m/^<?\Q$param->{msgid}\E>?$/i) {
         $docid = $line;
         last;
      } else {
         $line++;
      }
   }
   close(MSGIDS);

   if (not defined $docid) {
      print qq|
      <html>
      <head><title>Not Found</title>
      <body>
      <center>
      <a href="http://openwebmail.acatysmoof.com"><img src="/images/openwebmail.gif" border="0"></a><br><br>
      <p>The message id $param->{msgid} was not found.</p>
      </center>
      </body>
      </html>
      |;
   } else {
      if ($param->{orig}) {
         # they want the original
         print qq|
         <html>
         <head><title>Not Implemented</title>
         <body>
         <center>
         <a href="http://openwebmail.acatysmoof.com"><img src="/images/openwebmail.gif" border="0"></a><br><br>
         <p>The "Original Raw Message" feature is not implemented yet. Sorry for any inconvenience.</p>
         </center>
         </body>
         </html>
         |;
      } else {
         # redirect to the message uri
         $line = 0;
         open(URIS, "<$config->{uris}") or croak("Can't open uri file $config->{uris}\n");
         while (<URIS>) {
            $line++;
            next until $line == $docid;
            chomp;
            s#.*?/(archive/html/.*)#/$1#;
            print redirect($_);
         }
         close(URIS);
      }
   }
}


#use Data::Dumper;
#print header();
#print Dumper ($param);

# Show Original
# $SEARCH-CGI$?msgid=$MSGID:U$&amp;original=1

# Permanent Link to MSG
# $SEARCH-CGI$?msgid=$MSGID:U$












