date=`date "+%y%m%d"`

echo send openwebmail-current.tgz to mirror sites?
read ans
if [ "$ans" = "y" -o "$ans" = "Y" ]; then
  echo sending to mirror sites...

  echo "openwebmail current $date"| \
  /usr/local/bin/mutt -s "openwebmail current $date" \
  -a /usr/local/www/data/openwebmail/download/openwebmail-current.tgz \
  -a /usr/local/www/data/openwebmail/download/doc/changes.txt \
  openwebmail@turtle.ee.ncku.edu.tw \
  tchung@lmitlinux.jpl.nasa.gov 
#  elitric@hotmail.com 
fi

echo send openwebmail-current.tgz/chnages.txt to translators?
read ans
if [ "$ans" = "y" -o "$ans" = "Y" ]; then
  echo sending to translators...

  echo "openwebmail current $date">/tmp/mktgz.tmp.$$
  q /tmp/mktgz.tmp.$$
  cat /tmp/mktgz.tmp.$$| \
  /usr/local/bin/mutt -s "openwebmail current $date" \
  -a /usr/local/www/data/openwebmail/download/openwebmail-current.tgz \
  -a /usr/local/www/data/openwebmail/download/doc/changes.txt \
  st@e-puntcom.com \
  ruisb@ig.com.br \  
  gumo@lucifer.kgt.bme.hu \
  ful_s@fazekas.hu \
  jferra@sfconsultores.pt \
  flood@flood-net.de \
  lubos@klokner.sk \
  c.sabatier@bocquet.com \
  tryfan@telia.com \
  jablonski@dialogok.pl \
  jsmaldone@yahoo.com \
  wjun@mail.iap.ac.cn \
  michiel@connectux.com \
  lvm@mystery.lviv.net \
  kivilahti@exdecfinland.org \
  heljalaitinen@hotmail.com \
  michal@stavlib.hiedu.cz \
  duster@tpu.ru

  echo "openwebmail current $date is available at
http://turtle.ee.ncku.edu.tw/openwebmail/download/openwebmail-current.tgz">/tmp/mktgz.tmp.$$
  q /tmp/mktgz.tmp.$$
  cat /tmp/mktgz.tmp.$$| \
  /usr/local/bin/mutt -s "openwebmail current $date" \
  -a /usr/local/www/data/openwebmail/download/doc/changes.txt \
  i3100579@ingstud.units.it \
  frank@post12.tele.dk

  rm /tmp/mktgz.tmp.$$
fi
