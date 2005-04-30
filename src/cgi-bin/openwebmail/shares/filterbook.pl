#
# statbook.pl - read/write stationery book
#

use strict;
use Fcntl qw(:DEFAULT :flock);

use vars qw(%config %lang_err);
use vars qw(%op_order %ruletype_order %folder_order);	# filterrule prefered order, the smaller one is prefered

%op_order=(
   copy   => 0,
   move   => 1,
   delete => 2,
);

%ruletype_order=(
   from        => 0,
   to          => 1,
   subject     => 2,
   header      => 3,
   smtprelay   => 4,
   attfilename => 5,
   textcontent => 6
);

%folder_order=(		# folders not listed have order 0
   INBOX        => -1,
   DELETE       => 1,
   'virus-mail' => 2,
   'spam-mail'  => 3,
   'mail-trash' => 4
);

########## SORT_FILTERRULES #####################################
sub sort_filterrules {
   my ($r_filterrules)=@_;
   return sort {
               ${$r_filterrules}{$a}{priority}              <=> ${$r_filterrules}{$b}{priority}              or
               $op_order{${$r_filterrules}{$a}{op}}         <=> $op_order{${$r_filterrules}{$b}{op}}         or
               $ruletype_order{${$r_filterrules}{$a}{type}} <=> $ruletype_order{${$r_filterrules}{$b}{type}} or
               $folder_order{${$r_filterrules}{$a}{dest}}   <=> $folder_order{${$r_filterrules}{$b}{dest}}
               } keys %{$r_filterrules};
}
########## END SORT_FILTERRULES #################################

########## READ_FILTERBOOK ######################################
sub read_filterbook {
   my ($filterbookfile, $r_filterrules)=@_;

   if ( -f $filterbookfile ) {
      sysopen(FILTER, $filterbookfile, O_RDONLY) or
         return (-1, "$lang_err{'couldnt_read'} $filterbookfile! ($!)");
      while (<FILTER>) {
         chomp($_);
         if (/^\d+\@\@\@/) { # add valid rule only (Filippo Dattola)
            my %rule; @rule{'priority', 'type', 'inc', 'text', 'op', 'dest', 'enable', 'charset'}=split(/\@\@\@/);
            $rule{dest}=safefoldername($rule{dest});
            next if (!is_defaultfolder($rule{dest}) && !$config{'enable_userfolders'});
            my $key=join('@@@', @rule{'type', 'inc', 'text', 'dest'});
            ${$r_filterrules}{$key}=\%rule;
         }
      }
      close(FILTER) or
         return(-2, "$lang_err{'couldnt_close'} $filterbookfile! ($!)");
   }
   return(0, '');
}
########## READ_FILTERBOOK ######################################

########## WRITE_FILTERBOOK ######################################
sub write_filterbook {
   my ($filterbookfile, $r_filterrules)=@_;

   my @sortedrules=sort_filterrules($r_filterrules);

   sysopen(FILTER, $filterbookfile, O_WRONLY|O_TRUNC|O_CREAT) or
      return (-1, "$lang_err{'couldnt_write'} $filterbookfile! ($!)");
   foreach (@sortedrules) {
      my %rule=%{${$r_filterrules}{$_}};
      print FILTER join('@@@', $rule{priority},
                               $rule{type},
                               $rule{inc},
                               $rule{text},
                               $rule{op},
                               $rule{dest},
                               $rule{enable},
                               $rule{charset})."\n";
   }
   close(FILTER) or
      return(-2, "$lang_err{'couldnt_close'} $filterbookfile! ($!)");

   return(0, '');
}
########## WRITE_FILTERBOOK ######################################

1;
