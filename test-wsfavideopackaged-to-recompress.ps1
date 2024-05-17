$Input |% {

    $_ | & test-wsfavideopackaged-to-bag.ps1 -AdditionalBags:@( "Preservation" )

}
