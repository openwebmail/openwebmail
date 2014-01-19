
#                              The BSD License
#
#  Copyright (c) 2009-2014, The OpenWebMail Project
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

# pop3book.pl - read/write pop3book

use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);
use MIME::Base64;

sub readpop3book {
   my ($pop3book, $r_accounts) = @_;

   my $i = 0;

   %{$r_accounts} = ();

   if (-f $pop3book) {
      if (!ow::filelock::lock($pop3book, LOCK_SH|LOCK_NB)) {
         writelog("cannot lock file $pop3book");
         return -1;
      }

      if (!sysopen(POP3BOOK, $pop3book, O_RDONLY)) {
         writelog("cannot open file $pop3book ($!)");
         return -1;
      }

      while (my $line = <POP3BOOK>) {
      	 chomp($line);

         my @a = split(/\@\@\@/, $line);

         my ($pop3host, $pop3port, $pop3ssl, $pop3user, $pop3passwd, $pop3del, $enable) = @a;

         if ($#a == 5) {
            # for backward compatibility
            ($pop3host, $pop3port, $pop3user, $pop3passwd, $pop3del, $enable) = @a;
            $pop3ssl = 0;
         }

         $pop3passwd = decode_base64($pop3passwd);
         $pop3passwd = $pop3passwd ^ substr($pop3host, 5, length($pop3passwd));
         $r_accounts->{"$pop3host:$pop3port\@\@\@$pop3user"} = "$pop3host\@\@\@$pop3port\@\@\@$pop3ssl\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3del\@\@\@$enable";
         $i++;
      }

      close(POP3BOOK) or writelog("cannot close file $pop3book ($!)");

      ow::filelock::lock($pop3book, LOCK_UN) or writelog("cannot unlock file $pop3book");
   }

   return $i;
}

sub writepop3book {
   my ($pop3book, $r_accounts) = @_;

   $pop3book = ow::tool::untaint($pop3book);

   if (! -f $pop3book) {
      if (!sysopen(POP3BOOK, $pop3book, O_WRONLY|O_TRUNC|O_CREAT)) {
         writelog("cannot open file $pop3book ($!)");
         return -1;
      }

      close(POP3BOOK) or writelog("cannot close file $pop3book");
   }

   if (!ow::filelock::lock($pop3book, LOCK_EX)) {
      writelog("cannot lock file $pop3book");
      return -1;
   }

   if (!sysopen(POP3BOOK, $pop3book, O_WRONLY|O_TRUNC|O_CREAT)) {
      writelog("cannot open file $pop3book ($!)");
      return -1;
   }

   foreach my $account (values %{$r_accounts}) {
     chomp($account);

     my ($pop3host, $pop3port, $pop3ssl, $pop3user, $pop3passwd, $pop3del, $enable) = split(/\@\@\@/, $account);

     # not secure, but better than plaintext
     $pop3passwd = $pop3passwd ^ substr($pop3host, 5, length($pop3passwd));
     $pop3passwd = encode_base64($pop3passwd, '');
     print POP3BOOK "$pop3host\@\@\@$pop3port\@\@\@$pop3ssl\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3del\@\@\@$enable\n";
   }

   close(POP3BOOK) or writelog("cannot close file $pop3book ($!)");

   ow::filelock::lock($pop3book, LOCK_UN) or writelog("cannot unlock file $pop3book");

   return 0;
}

1;
