function listener (event) {
  if ( event.origin !== "https://www.araport.org" )
    return

  var apiToken = document.getElementById("api-token");
  apiToken.value = event.data;
  angular.element(apiToken).triggerHandler('input');
}
