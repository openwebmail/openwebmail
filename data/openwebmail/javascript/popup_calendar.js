// this module requires the popup_base.js library file
// be loaded to provide the dhtml layer support
//
// given a year, month, and day, create a calendar popup
// perform the user defined callback when a date is selected
//
// the callback is a user-defined function
// it will be called like: callback(year,month,day)
//
// EXAMPLE:
// funtion mycustomclose(year,month,day) { alert(year+' '+month+' '+day) };
// <a onclick="calPopup(this,'2009','12','06','mycustomclose','mypopupdivid',-175,15);"><img src="cal.gif"></a>

var calHtml = '';

function calPopup(caller, year, month, day, callback, id, xOffset, yOffset) {
   attachListener(id);
   registerPopup(id);
   calHtml = makeCalHtml(id, year, month, day, callback);
   writeLayer(id, calHtml);
   setLayerPos(caller, id, xOffset, yOffset);
   showLayer(id);
   return true;
}

function makeCalHtml(id, year, month, day, callback) {
   var todayDate = new Date();

   // use today as the date if year, month, day are not valid numbers
   year = isNaN(parseInt(year,10)) ? todayDate.getFullYear() : year;
   month = isNaN(parseInt(month,10)) ? todayDate.getMonth() + 1 : month;
   day = isNaN(parseInt(day,10)) ? todayDate.getDate() : day;

   var daysInMonth = new Array(0,31,28,31,30,31,30,31,31,30,31,30,31);

   if ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) {
      daysInMonth[2] = 29;
   }

   var calDate = new Date(year, month - 1, day);

   // check if the currently selected day is more than what our target month has
   if (month < calDate.getMonth() + 1) {
     day = day - calDate.getDate();
     calDate = new Date(year, month - 1, day);
   }

   var nextyear  = calDate.getMonth() == 11 ? calDate.getFullYear() + 1 : calDate.getFullYear();
   var nextmonth = calDate.getMonth() == 11 ? 1 : calDate.getMonth() + 2;

   var lastyear  = calDate.getMonth() == 0 ? calDate.getFullYear() - 1 : calDate.getFullYear();
   var lastmonth = calDate.getMonth() == 0 ? 12 : calDate.getMonth();

   // this relies on the javascript bug-feature of offsetting values over 31 days properly.
   // Negative day offsets do NOT work with Netscape 4.x, and negative months do not work
   // in Safari. This hack works everywhere.
   var calStartOfThisMonthDate = new Date(year,month-1,1);
   var calOffsetToFirstDayOfLastMonth = calStartOfThisMonthDate.getDay() >= wStart ? calStartOfThisMonthDate.getDay()-wStart : 7-wStart-calStartOfThisMonthDate.getDay()
   if (calOffsetToFirstDayOfLastMonth > 0) {
      var calStartDate = new Date(lastyear,lastmonth-1,1); // we start in last month
   } else {
      var calStartDate = new Date(year,month-1,1); // we start in this month
   }
   var calStartYear = calStartDate.getFullYear();
   var calStartMonth = calStartDate.getMonth();
   var calCurrentDay = calOffsetToFirstDayOfLastMonth ? daysInMonth[calStartMonth+1]-(calOffsetToFirstDayOfLastMonth-1) : 1;

   var html = '';
   // writing the <html><head><body> causes some browsers (Konquerer) to fail
   html += '<table cellpadding="0" cellspacing="1" border="0" bgcolor="#000000">\n';
   html += '<tr>\n';
   html += '<td valign="top">\n';
   html += '<table cellpadding="2" cellspacing="0" border="0">\n';
   html += '<tr>\n';
   html += '<td valign="top" class="menubar">\n';
   html += '<table cellpadding="3" cellspacing="1" border="0">\n';
   html += '<tr>\n';
   html += '<td class="menubar"><a class="stylecal" href="javascript:void(0);" onclick="updateCal(\''+id+'\','+lastyear+','+lastmonth+','+day+',\''+callback+'\'); return false;">&lt;&lt;</a></td>\n';
   html += '<td align="center" colspan="5" class="menubar stylecal">&nbsp;' +wMonth[calDate.getMonth()]+ ' ' +calDate.getFullYear()+ '&nbsp;</td>\n';
   html += '<td class="menubar"><a class="stylecal" href="javascript:void(0);" onclick="updateCal(\''+id+'\','+nextyear+','+nextmonth+','+day+',\''+callback+'\'); return false;">&gt;&gt;</a></td>\n';
   html += '</tr>\n';
   for (var row=1; row <= 7; row++) {
      // check if we started a new month at the beginning of this row
      upcomingDate = new Date(calStartYear,calStartMonth,calCurrentDay);
      if (upcomingDate.getDate() <= 8 && row > 5) {
         continue; // skip this row
      }

      html += '<tr>\n';
      for (var col=0; col < 7; col++) {
         var tdClass = col % 2 ? '"rowdark"' : '"rowlight"';
         if (row == 1) {
            html += '<td class='+tdClass+' align="center"><span class="stylecal">'+wDayAbbrev[(wStart+col)%7]+'</span></td>\n';
         } else {
            var hereDate = new Date(calStartYear,calStartMonth,calCurrentDay,12,0,0);
            var hereDay = hereDate.getDate();
            var aClass = '"stylecal"';

            if (hereDate.getYear() == todayDate.getYear() && hereDate.getMonth() == todayDate.getMonth() && hereDate.getDate() == todayDate.getDate()) {
               tdClass = '"todayhilite"';
            }
            if (hereDate.getMonth() != calDate.getMonth()) {
               tdClass = '"menubar"';
               aClass = '"notmonth"';
            }

            html += '<td class='+tdClass+' align="right"><a class='+aClass+' href="javascript:void(0);" onClick="eval('+callback+'(\''+hereDate.getFullYear()+'\',\''+(hereDate.getMonth()+1)+'\',\''+hereDate.getDate()+'\')); hideLayer(\''+id+'\'); return false;">'+hereDay+'</a></td>\n';
            calCurrentDay++;
         }
      }
      html += '</tr>\n';
   }
   html += '<tr>\n';
   html += '<td align="center" colspan="7"><a class="stylecal" href="javascript:void(0);" onClick="updateCal(\''+id+'\','+todayDate.getFullYear()+','+(todayDate.getMonth()+1)+','+todayDate.getDate()+',\''+callback+'\'); return false;">'+wToday+'</a></td>\n';
   html += '</tr>\n';
   html += '</table>\n';
   html += '</td>\n';
   html += '</tr>\n';
   html += '</table>\n';
   html += '</td>\n';
   html += '</tr>\n';
   html += '</table>\n';

   return html;
}

function updateCal(id, year, month, day, callback) {
   calHtml = makeCalHtml(id, year, month, day, callback);
   writeLayer(id, calHtml);
}

