$Input |% {

    $_ | & test-wsfavideo-packaged-to-bag.ps1 -AdditionalBags:@( "Preservation" )

}
