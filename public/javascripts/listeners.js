function listener (event) {
  if ( event.origin === "https://www.araport.org" || event.origin === "https://araport-dev.tacc.utexas.edu" ) {
    var apiToken = document.getElementById("api-token");
    apiToken.value = event.data;
    angular.element(apiToken).triggerHandler('input');
  } else {
    return;
  }
}
