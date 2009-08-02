// When you want to include a DHTML popup in a page you MUST:
// 1) create a named div for the popup to attach to in the page.
//    It should look like <div id="mypopup"></div>. Do not put
//    the div anywhere in a table. It should be outside tables.
// 2) create a stylesheet id selector entry for your div. It
//    MUST be position absolute and should look like:
//    #mypopup{ position: absolute;
//              visibility: hidden;
//              background-color: "#AABBCC";
//              layer-background-color: "#AABBCC"; }
// 3) call the popup with code that looks like
//    <a href="#" onClick="calPopup(this,'mypopup',-175,15,'additemform','valiDate');">
//    where -175 and 15 are your desired x and y offsets from the link.
//    The final argument indicates the validation script to run after
//    the popup makes a change to the form. This argument is optional.

var nn4 = (document.layers) ? true : false;
var ie  = (document.all) ? true : false;
var dom = (document.getElementById && !document.all) ? true : false;
var popups = new Array(); // keeps track of popup windows we create

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

