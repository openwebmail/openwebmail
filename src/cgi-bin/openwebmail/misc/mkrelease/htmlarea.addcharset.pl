%languagecharsets =(
   'ar.CP1256'    => 'windows-1256',
   'ar.ISO8859-6' => 'iso-8859-6',
   'bg'           => 'windows-1251',
   'ca'           => 'iso-8859-1',
   'cs'           => 'iso-8859-2',
   'da'           => 'iso-8859-1',
   'de'           => 'iso-8859-1',
   'en'           => 'iso-8859-1',
   'el'           => 'iso-8859-7',
   'es'           => 'iso-8859-1',
   'fi'           => 'iso-8859-1',
   'fr'           => 'iso-8859-1',
   'he.CP1255'    => 'windows-1255',	# charset only, lang/template not translated
   'he.ISO8859-8' => 'iso-8859-8',	# charset only, lang/template not translated
   'hu'           => 'iso-8859-2',
   'id'           => 'iso-8859-1',
   'it'           => 'iso-8859-1',
   'ja_JP.eucJP'     => 'euc-jp',
   'ja_JP.Shift_JIS' => 'shift_jis',
   'kr'           => 'euc-kr',
   'lt'           => 'windows-1257',
   'nl'           => 'iso-8859-1',
   'no'           => 'iso-8859-1',
   'pl'           => 'iso-8859-2',
   'pt'           => 'iso-8859-1',
   'pt_BR'        => 'iso-8859-1',
   'ro'           => 'iso-8859-2',
   'ru'           => 'koi8-r',
   'sk'           => 'iso-8859-2',
   'sr'           => 'iso-8859-2',
   'sv'           => 'iso-8859-1',
   'th'           => 'tis-620',
   'tr'           => 'iso-8859-9',
   'uk'           => 'koi8-u',
   'ur'           => 'utf-8',
   'zh_CN.GB2312' => 'gb2312',
   'zh_TW.Big5'   => 'big5',
   'utf-8'        => 'utf-8'		# charset only, use en lang/template
);

foreach my $d (keys %languagecharsets) {
   foreach my $file ("about.html", "insert_table.html", "insert_image.html", "select_color.html") {
      next if (! -f "$d/$file");
      my $data;

      print "$d/$file\n";
      open (T, "$d/$file") || die $!;
      local $/; undef $/; $data=<T> || die $!;
      close (T);

      my $h=qq|<meta http-equiv="Content-Type" content="text/html; charset=$languagecharsets{$d}">|;
      $data=~s/<title/$h\n  <title/is;

#      open (T, ">$d/$file");
#      print T $data;
#      close (T);
   }
}
