function cal_update_recurrence(formName) {
   // update the recurrance pulldowns to reflect the currently selected event date
   var formYear = document.forms[formName].elements['year'].options[document.forms[formName].elements['year'].selectedIndex].value;
   var formMonth = document.forms[formName].elements['month'].options[document.forms[formName].elements['month'].selectedIndex].value;
   var formDay = document.forms[formName].elements['day'].options[document.forms[formName].elements['day'].selectedIndex].value;
   var dayfreqSelection = document.forms[formName].elements['dayfreq'].selectedIndex;
   var monthfreqSelection = document.forms[formName].elements['monthfreq'].selectedIndex;
   var checkDate = new Date(formYear,formMonth-1,formDay);

   if (formMonth < checkDate.getMonth()+1) {
     var selectedmonth=document.forms[formName].elements['month'].options[document.forms[formName].elements['month'].selectedIndex].text;
     var daysinmonth=formDay-checkDate.getDate();
     alert(alerttxt(selectedmonth,daysinmonth,formYear,daysinmonth));
     document.forms[formName].elements['day'].selectedIndex = formDay-checkDate.getDate()-1;
     // reset our vars
     formDay = formDay-checkDate.getDate();
     checkDate = new Date(formYear,formMonth-1,formDay);
   }

   var weekOrder = parseInt((parseInt(formDay)+6)/7);

   // update the day recurrance
   if (weekOrder<=4) {
      if (! document.forms[formName].elements['dayfreq'][2]) {  // coming from 2 choice menu
         if (dayfreqSelection==1) {
            dayfreqSelection++;
         }
      }
      document.forms[formName].elements['dayfreq'].options.length =0; // clear popup
      document.forms[formName].elements['dayfreq'][0] = new Option(thisdayonlytxt,"thisdayonly");
      document.forms[formName].elements['dayfreq'][1] = new Option(thewdayofthismonthtxt(weekOrder,checkDate.getDay()),"thewdayofthismonth");
      document.forms[formName].elements['dayfreq'][2] = new Option(everywdaythismonthtxt(checkDate.getDay()),"everywdaythismonth");
   } else {
      if (document.forms[formName].elements['dayfreq'][2]) {  // coming from 3 choice menu
         dayfreqSelection = dayfreqSelection - 1;
         if (dayfreqSelection < 0) {
            dayfreqSelection = 0;
         }
      }
      document.forms[formName].elements['dayfreq'].options.length =0; // clear popup
      document.forms[formName].elements['dayfreq'][0] = new Option(thisdayonlytxt,"thisdayonly");
      document.forms[formName].elements['dayfreq'][1] = new Option(everywdaythismonthtxt(checkDate.getDay()),"everywdaythismonth");
   }

   // update the month recurrance
   if (formMonth%2) {
      document.forms[formName].elements['monthfreq'][1] = new Option(everyoddmonththisyeartxt,"everyoddmonththisyear");
   } else {
      document.forms[formName].elements['monthfreq'][1] = new Option(everyevenmonththisyeartxt,"everyevenmonththisyear");
   }

   document.forms[formName].elements['dayfreq'].selectedIndex = dayfreqSelection;
   document.forms[formName].elements['monthfreq'].selectedIndex = monthfreqSelection;
   return true;
}

