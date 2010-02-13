function make_label(count) {
   // given an address count number, create the label based on the address field values
   var street            = document.editForm.elements['ADR.'+count+'.VALUE.STREET'].value;
   var extendedaddress   = document.editForm.elements['ADR.'+count+'.VALUE.EXTENDEDADDRESS'].value;
   var postofficeaddress = document.editForm.elements['ADR.'+count+'.VALUE.POSTOFFICEADDRESS'].value;
   var locality          = document.editForm.elements['ADR.'+count+'.VALUE.LOCALITY'].value;
   var region            = document.editForm.elements['ADR.'+count+'.VALUE.REGION'].value;
   var postalcode        = document.editForm.elements['ADR.'+count+'.VALUE.POSTALCODE'].value;
   var country           = document.editForm.elements['ADR.'+count+'.VALUE.COUNTRY'].value;

   var label = '';

   label += postofficeaddress != '' ? postofficeaddress+'\n' : '';

   if (street != '' && extendedaddress != '') {
      label += street+', '+extendedaddress+'\n';
   } else if (street != '') {
      label += street+'\n';
   } else if (extendedaddress != '') {
      label += extendedaddress+'\n';
   }

   if (locality != '' && region != '') {
      label += locality+', '+region+'\n';
   } else if (locality != '') {
      label += locality+'\n';
   } else if (region != '') {
      label += region+'\n';
   }

   if (postalcode != '' && country != '') {
      label += '         '+postalcode+' '+country;
   } else if (postalcode != '') {
      label += '         '+postalcode;
   } else if (country != '') {
      label += '         '+country;
   }

   document.editForm.elements['ADR.'+count+'.VALUE.LABEL'].value = label;
}
