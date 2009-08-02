// create a calendar popup
// this requires also loading the popup.js library file

var calHtml = '';

function calPopup(obj, id, xOffset, yOffset, formName, validationScript) {
   attachListener(id);
   registerPopup(id);
   calHtml = makeCalHtml(id,null,null,null,formName,validationScript);
   writeLayer(id,calHtml);
   setLayerPos(obj,id,xOffset,yOffset);
   showLayer(id);
   return true;
}

function makeCalHtml(id, calYear, calMonth, calDay, formName, validationScript) {
   var calYear = calYear ? calYear : document.forms[formName].elements['year'].options[document.forms[formName].elements['year'].selectedIndex].value;
   var calMonth = calMonth ? calMonth : document.forms[formName].elements['month'].options[document.forms[formName].elements['month'].selectedIndex].value;
   var calDay = calDay ? calDay : document.forms[formName].elements['day'].options[document.forms[formName].elements['day'].selectedIndex].value;

   var daysInMonth = new Array(0,31,28,31,30,31,30,31,31,30,31,30,31);
   if ((calYear % 4 == 0 && calYear % 100 != 0) || calYear % 400 == 0) {
      daysInMonth[2] = 29;
   }

   var calDate = new Date(calYear,calMonth-1,calDay);

   //-----------------------------------------
   // check if the currently selected day is
   // more than what our target month has
   //-----------------------------------------
   if (calMonth < calDate.getMonth()+1) {
     calDay = calDay-calDate.getDate();
     calDate = new Date(calYear,calMonth-1,calDay);
   }

   var calNextYear  = calDate.getMonth() == 11 ? calDate.getFullYear()+1 : calDate.getFullYear();
   var calNextMonth = calDate.getMonth() == 11 ? 1 : calDate.getMonth()+2;
   var calLastYear  = calDate.getMonth() == 0 ? calDate.getFullYear()-1 : calDate.getFullYear();
   var calLastMonth = calDate.getMonth() == 0 ? 12 : calDate.getMonth();

   var todayDate = new Date();

   //---------------------------------------------------------
   // this relies on the javascript bug-feature of offsetting
   // values over 31 days properly. Negative day offsets do NOT
   // work with Netscape 4.x, and negative months do not work
   // in Safari. This works everywhere.
   //---------------------------------------------------------
   var calStartOfThisMonthDate = new Date(calYear,calMonth-1,1);
   var calOffsetToFirstDayOfLastMonth = calStartOfThisMonthDate.getDay() >= wStart ? calStartOfThisMonthDate.getDay()-wStart : 7-wStart-calStartOfThisMonthDate.getDay()
   if (calOffsetToFirstDayOfLastMonth > 0) {
      var calStartDate = new Date(calLastYear,calLastMonth-1,1); // we start in last month
   } else {
      var calStartDate = new Date(calYear,calMonth-1,1); // we start in this month
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
   html += '<td class="menubar"><a class="stylecal" href="#" onClick="updateCal(\''+id+'\','+calLastYear+','+calLastMonth+','+calDay+',\''+formName+'\',\''+validationScript+'\'); return false;">&lt;&lt;</a></td>\n';
   html += '<td align="center" colspan="5" class="menubar stylecal">&nbsp;' +wMonth[calDate.getMonth()]+ ' ' +calDate.getFullYear()+ '&nbsp;</td>\n';
   html += '<td class="menubar"><a class="stylecal" href="#" onClick="updateCal(\''+id+'\','+calNextYear+','+calNextMonth+','+calDay+',\''+formName+'\',\''+validationScript+'\'); return false;">&gt;&gt;</a></td>\n';
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

            html += '<td class='+tdClass+' align="right"><a class='+aClass+' href="#" onClick="changeFormDate('+hereDate.getFullYear()+','+(hereDate.getMonth()+1)+','+hereDate.getDate()+',\''+formName+'\',\''+validationScript+'\'); hideLayer(\''+id+'\'); return false;">'+hereDay+'</a></td>\n';
            calCurrentDay++;
         }
      }
      html += '</tr>\n';
   }
   html += '<tr>\n';
   html += '<td align="center" colspan="7"><a class="stylecal" href="#" onClick="updateCal(\''+id+'\','+todayDate.getFullYear()+','+(todayDate.getMonth()+1)+','+todayDate.getDate()+',\''+formName+'\',\''+validationScript+'\'); return false;">Today</a></td>\n';
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

function updateCal(id, calYear, calMonth, calDay, formName, validationScript) {
   calHtml = makeCalHtml(id,calYear,calMonth,calDay,formName,validationScript);
   writeLayer(id,calHtml);
}

function changeFormDate(changeYear,changeMonth,changeDay,formName,validationScript) {
   document.forms[formName].elements['year'].selectedIndex = changeYear-min_year;
   document.forms[formName].elements['month'].selectedIndex = changeMonth-1;
   document.forms[formName].elements['day'].selectedIndex = changeDay-1;
   if (validationScript) {
      eval(validationScript+"('"+formName+"')"); // to update the other selection boxes in the form
   }
}
