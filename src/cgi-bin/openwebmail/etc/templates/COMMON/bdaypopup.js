<script type="text/javascript" language="javascript">
<!--
// BDAY calpopup. See calpopup.js for usage instructions.

var nn4 = (document.layers) ? true : false;
var ie  = (document.all) ? true : false;
var dom = (document.getElementById && !document.all) ? true : false;
var popups = new Array(); // keeps track of popup windows we create
var calHtml = '';
var checkedvalues = 0;

// language and preferences
wDay = new Array(@@@WDAY_ARRAY@@@);
wDayAbbrev = new Array(@@@WDAYABBREV_ARRAY@@@);
wMonth = new Array(@@@WMONTH_ARRAY@@@);
wOrder = new Array(@@@WORDER_ARRAY@@@);
wStart = @@@WSTART@@@;

function calPopup(obj, id, xOffset, yOffset, formName, validationScript) {
   checkedvalues = 0;
   attachListener(id);
   registerPopup(id);
   calHtml = makeCalHtml(id,null,null,null,formName,validationScript);
   writeLayer(id,calHtml);
   setLayerPos(obj,id,xOffset,yOffset);
   showLayer(id);
   return true;
}

function attachListener(id) {
   var layer = new pathToLayer(id)
   if (layer.obj.listening == null) {
      document.oldMouseupEvent = document.onmouseup;
      if (document.oldMouseupEvent != null) {
         document.onmouseup = new Function("document.oldMouseupEvent(); hideLayersNotClicked();");
      } else {
         document.onmouseup = hideLayersNotClicked;
      }
      layer.obj.listening = true;
   }
}

function registerPopup(id) {
   // register this popup window with the popups array
   var layer = new pathToLayer(id);
   if (layer.obj.registered == null) {
      var index = popups.length ? popups.length : 0;
      popups[index] = layer;
      layer.obj.registered = 1;
   }
}

function makeCalHtml(id, calYear, calMonth, calDay, formName, validationScript) {
   var todayDate = new Date();

   var calYear = calYear ? calYear : todayDate.getFullYear();   // returns a four digit integer representing the year
   var calMonth = calMonth ? calMonth : todayDate.getMonth()+1; // returns an integer (0 for January thru 11 for December)
   var calDay = calDay ? calDay : todayDate.getDay();           // returns an integer (0 for Sunday thru 6 for Saturday)

   // adjust the year and month the cal shows to match the form
   if (checkedvalues == 0) {
      if (document.forms[formName].elements['@@@YEAR.NAME@@@'].value != '' && !isNaN(document.forms[formName].elements['@@@YEAR.NAME@@@'].value)) {
         calYear = document.forms[formName].elements['@@@YEAR.NAME@@@'].value;
         checkedvalues++;
      } else if (document.forms[formName].elements['@@@AGE.NAME@@@'].value != '' && !isNaN(document.forms[formName].elements['@@@AGE.NAME@@@'].value)) {
         if (document.forms[formName].elements['@@@YEAR.NAME@@@'].value == '') {
            if (document.forms[formName].elements['@@@AGE.NAME@@@'].value > 0) {
               calYear = calYear - document.forms[formName].elements['@@@AGE.NAME@@@'].value;
               checkedvalues++;
            }
         }
      }
      if (document.forms[formName].elements['@@@MONTH.NAME@@@'].value != '' && !isNaN(document.forms[formName].elements['@@@MONTH.NAME@@@'].value)) {
         calMonth = document.forms[formName].elements['@@@MONTH.NAME@@@'].value;
         if (calMonth > 12) {
            calMonth = 12;
         }
         if (calMonth < 1) {
            calMonth = 1;
         }
         document.forms[formName].elements['@@@MONTH.NAME@@@'].value = calMonth;
      }
   }

   var daysInMonth = new Array(0,31,28,31,30,31,30,31,31,30,31,30,31);
   if ((calYear % 4 == 0 && calYear % 100 != 0) || calYear % 400 == 0) {
      daysInMonth[2] = 29;
   }

   var calDate = new Date(calYear,calMonth-1,calDay);

   // check if the currently selected day is more than what our target month has
   if (calMonth < calDate.getMonth()+1) {
     calDay = calDay-calDate.getDate();
     calDate = new Date(calYear,calMonth-1,calDay);
   }

   var calNextYear  = calDate.getMonth() == 11 ? calDate.getFullYear()+1 : calDate.getFullYear();
   var calNextMonth = calDate.getMonth() == 11 ? 1 : calDate.getMonth()+2;
   var calLastYear  = calDate.getMonth() == 0 ? calDate.getFullYear()-1 : calDate.getFullYear();
   var calLastMonth = calDate.getMonth() == 0 ? 12 : calDate.getMonth();


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
   html += '<table cellpadding="0" cellspacing="2" border="0" bgcolor=@@@MENUBAR@@@>\n';
   html += '<tr>\n';
   html += '<td valign="top">\n';
   html += '<table cellpadding="3" cellspacing="1" border="0">\n';
   html += '<tr>\n';
   html += '<td><a class="stylecal" href="#" onClick="updateCal(\''+id+'\','+calLastYear+','+calLastMonth+','+calDay+',\''+formName+'\',\''+validationScript+'\'); return false;">&lt;&lt;</a></td>\n';
   html += '<td class="stylecal" align="center" colspan="5">&nbsp;' +wMonth[calDate.getMonth()]+ ' ' +calDate.getFullYear()+ '&nbsp;</td>\n';
   html += '<td><a class="stylecal" href="#" onClick="updateCal(\''+id+'\','+calNextYear+','+calNextMonth+','+calDay+',\''+formName+'\',\''+validationScript+'\'); return false;">&gt;&gt;</a></td>\n';
   html += '</tr>\n';
   for (var row=1; row <= 7; row++) {
      // check if we started a new month at the beginning of this row
      upcomingDate = new Date(calStartYear,calStartMonth,calCurrentDay);
      if (upcomingDate.getDate() <= 8 && row > 5) {
         continue; // skip this row
      }

      html += '<tr>\n';
      for (var col=0; col < 7; col++) {
         var tdColor = col % 2 ? '@@@TABLEROW_DARK@@@' : '@@@TABLEROW_LIGHT@@@';
         if (row == 1) {
            html += '<td bgcolor='+tdColor+' align="center" class="stylecal">'+wDayAbbrev[(wStart+col)%7]+'</td>\n';
         } else {
            var hereDate = new Date(calStartYear,calStartMonth,calCurrentDay);
            var hereDay = hereDate.getDate();
            var aClass = '"stylecal"';

            if (hereDate.getYear() == todayDate.getYear() && hereDate.getMonth() == todayDate.getMonth() && hereDate.getDate() == todayDate.getDate()) {
               tdColor = '"#ff9999"';
            }
            if (hereDate.getMonth() != calDate.getMonth()) {
               tdColor = '@@@MENUBAR@@@';
               var aClass = '"notmonth"';
            }

            html += '<td bgcolor='+tdColor+' align="right"><a class='+aClass+' href="#" onClick="changeFormDate('+hereDate.getFullYear()+','+(hereDate.getMonth()+1)+','+hereDate.getDate()+',\''+formName+'\',\''+validationScript+'\'); hideLayer(\''+id+'\'); return false;">'+hereDay+'</a></td>\n';
            calCurrentDay++;
         }
      }
      html += '</tr>\n';
   }
   html += '<tr>\n';
   html += '<td align="center" colspan="7"><a class="stylecal" href="#" onClick="updateCal(\''+id+'\','+todayDate.getFullYear()+','+(todayDate.getMonth()+1)+','+todayDate.getDate()+',\''+formName+'\',\''+validationScript+'\'); return false;">@@@TODAY@@@</a></td>\n';
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

function writeLayer(id, html) {
   var layer = new pathToLayer(id);
   if (nn4) {
      layer.obj.document.open();
      layer.obj.document.write(html);
      layer.obj.document.close();
   } else {
      layer.obj.innerHTML = '';
      layer.obj.innerHTML = html;
   }
}

function setLayerPos(obj, id, xOffset, yOffset) {
   var newX = 0;
   var newY = 0;
   if (obj.offsetParent) {
      // if called from href="setLayerPos(this,'example')" then obj will
      // have no offsetParent properties. Use onClick= instead.
      while (obj.offsetParent) {
         newX += obj.offsetLeft;
         newY += obj.offsetTop;
         obj = obj.offsetParent;
      }
   } else if (obj.x) {
      // nn4 - only works with "a" tags
      newX += obj.x;
      newY += obj.y;
   }

   // apply the offsets
   newX += xOffset;
   newY += yOffset;

   // apply the new positions to our layer
   var layer = new pathToLayer(id);
   if (nn4) {
      layer.style.left = newX;
      layer.style.top  = newY;
   } else {
      // the px avoids errors with doctype strict modes
      layer.style.left = newX + 'px';
      layer.style.top  = newY + 'px';
   }
}

function hideLayersNotClicked(e) {
   if (!e) var e = window.event;
   e.cancelBubble = true;
   if (e.stopPropagation) e.stopPropagation();
   if (e.target) {
      var clicked = e.target;
   } else if (e.srcElement) {
      var clicked = e.srcElement;
   }

   // go through each popup window,
   // checking if it has been clicked
   for (var i=0; i < popups.length; i++) {
      if (nn4) {
         if ((popups[i].style.left < e.pageX) &&
             (popups[i].style.left+popups[i].style.clip.width > e.pageX) &&
             (popups[i].style.top < e.pageY) &&
             (popups[i].style.top+popups[i].style.clip.height > e.pageY)) {
            return true;
         } else {
            hideLayer(popups[i].obj.id);
            return true;
         }
      } else if (ie) {
         while (clicked.parentElement != null) {
            if (popups[i].obj.id == clicked.id) {
               return true;
            }
            clicked = clicked.parentElement;
         }
         hideLayer(popups[i].obj.id);
         return true;
      } else if (dom) {
         while (clicked.parentNode != null) {
            if (popups[i].obj.id == clicked.id) {
               return true;
            }
            clicked = clicked.parentNode;
         }
         hideLayer(popups[i].obj.id);
         return true;
      }
      return true;
   }
   return true;
}

function pathToLayer(id) {
   if (nn4) {
      this.obj = document.layers[id];
      this.style = document.layers[id];
   } else if (ie) {
      this.obj = document.all[id];
      this.style = document.all[id].style;
   } else {
      this.obj = document.getElementById(id);
      this.style = document.getElementById(id).style;
   }
}

function showLayer(id) {
   var layer = new pathToLayer(id)
   layer.style.visibility = "visible";
}

function hideLayer(id) {
   var layer = new pathToLayer(id);
   layer.style.visibility = "hidden";
}

function changeFormDate(changeYear,changeMonth,changeDay,formName,validationScript) {
   document.forms[formName].elements['@@@YEAR.NAME@@@'].value = changeYear;
   document.forms[formName].elements['@@@MONTH.NAME@@@'].value = changeMonth;
   document.forms[formName].elements['@@@DAY.NAME@@@'].value = changeDay;
   calculateAge(formName, changeYear);
   // if (validationScript) {
   //    eval(validationScript+"('"+formName+"')"); // to update the other selection boxes in the form
   // }
}

function calculateAge(formName) {
   var todayDate = new Date();
   var todayYear = todayDate.getFullYear();
   var todayMonth = todayDate.getMonth()+1;
   var todayDay = todayDate.getDate();
   var formDay = validateDay(formName,document.forms[formName].elements['@@@DAY.NAME@@@'].value);
   var formMonth = validateMonth(formName,document.forms[formName].elements['@@@MONTH.NAME@@@'].value);
   var formYear = validateYear(formName,document.forms[formName].elements['@@@YEAR.NAME@@@'].value);
   var age = 0;
   if (formYear != '') {
      age = todayYear - formYear;
      if (formMonth != '') {
         if (todayMonth < formMonth) {
            age--; // birthday hasn't happened yet
         } else if (formMonth == todayMonth && formDay != '' && todayDay < formDay) {
            age--; // birthday hasn't happened yet
         }
      }
   }
   if (age < 0) {
      age = 0;
   }
   document.forms[formName].elements['@@@AGE.NAME@@@'].value = age?age:'';
}

function calculateYearFromAge(formName, formAge) {
   var todayDate = new Date();
   var todayYear = todayDate.getFullYear();
   var todayMonth = todayDate.getMonth()+1;
   var todayDay = todayDate.getDate();
   var formDay = validateDay(formName,document.forms[formName].elements['@@@DAY.NAME@@@'].value);
   var formMonth = validateMonth(formName,document.forms[formName].elements['@@@MONTH.NAME@@@'].value);
   var formYear = '';
   formAge = validateAge(formName,formAge);
   if (formAge != '') {
      formYear = todayYear - formAge;
      if (formMonth != '') {
         if (todayMonth < formMonth) {
            formYear--;
         } else if (formMonth == todayMonth && formDay != '' && todayDay < formDay) {
            formYear--;
         }
      }
   }
   document.forms[formName].elements['@@@YEAR.NAME@@@'].value = formYear;
}

function validateMonth(formName, calMonth) {
   if (calMonth != '') {
      if (isNaN(calMonth)) {
         calMonth = 1;
      } else {
         if (calMonth > 12) {
            calMonth = 12;
         }
         if (calMonth < 1) {
            calMonth = 1;
         }
      }
      document.forms[formName].elements['@@@MONTH.NAME@@@'].value = calMonth;
      return calMonth;
   } else {
      return '';
   }
}

function validateDay(formName, calDay) {
   if (calDay != '') {
      if (isNaN(calDay)) {
         calDay = 1;
      } else {
         if (calDay > 31 || calDay < 1) {
            calDay = 1;
         }
      }
      document.forms[formName].elements['@@@DAY.NAME@@@'].value = calDay;
      return calDay;
   } else {
      return '';
   }
}

function validateYear(formName, calYear) {
   var todayDate = new Date();
   if (calYear != '') {
      if (isNaN(calYear)) {
         calYear = todayDate.getFullYear();
      } else {
         if (calYear < 100) {
            calYear = 100;
         }
      }
      document.forms[formName].elements['@@@YEAR.NAME@@@'].value = calYear;
      return calYear;
   } else {
      return '';
   }
}

function validateAge(formName, formAge) {
   if (isNaN(formAge) || formAge < 0) {
      formAge = 0;
   }
   document.forms[formName].elements['@@@AGE.NAME@@@'].value = formAge;
   return formAge;
}
// -->
</script>

