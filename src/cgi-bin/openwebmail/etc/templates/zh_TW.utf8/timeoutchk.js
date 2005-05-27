<script language="JavaScript">
<!--
   // alert before session end
   var remainingseconds=@@@REMAININGSECONDS@@@;
   var url = "@@@PREFSURL@@@?action=timeoutwarning&sessionid=@@@SESSIONID@@@&session_noupdate=1";
   var tid;
   var hWnd;
   var warn=0;

   function timeoutcheck () {
      remainingseconds=remainingseconds-1;
      if (remainingseconds>0) {
         tid=setTimeout("timeoutcheck()", 1*1000);
         if (remainingseconds<65) {
            if (remainingseconds>6) {
               window.defaultStatus="Session 時間 : 倒數 "+ (remainingseconds-5) +" 秒";
            } else if (remainingseconds>=5) {
               window.defaultStatus="Session 時間 : 倒數 "+ (remainingseconds-5) +" 秒";
            }
            if (!warn) {
               warn=1;
               @@@JSCODE@@@
               hWnd = window.open(url,"_timeoutwarning","width=400,height=140,resizable=no,scrollbars=no");
               hWnd.focus();
            }
         }
      } else {
         window.defaultStatus="Session 時間結束";
         clearTimeout(tid);
      }
   }

   function sessioncheck () {
      if (remainingseconds>0) {
         return true;
      } else {
         alert("很抱歉, 您的作業階段已經遹時, 請重新登入");
         return false;
      }
   }

   timeoutcheck();
//-->
</script>
