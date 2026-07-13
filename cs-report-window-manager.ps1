& wait-maintenanceschedule.ps1 -By:"10:30 PM" -Label:"DA-Masters: Q / SC / AMG / WSFA / Digitized_newspapers / Legislative_publications / NAGPRA / Genealogy_history / Executive_orders / Robinson DigitalMasters reporting" -Job:{
    cd H:\Holdings\Digitization\Masters
    Get-Item .\Bryan_Carter_photos,
        .\AMG\Discs,
        .\Digitized_newspapers,
        .\Genealogy_history,
        .\Goldstar,
        .\Legislative_publications,
        .\NAGPRA,
        .\Robinson -Force | out-321preservationreport.ps1 -Attn -Bags -Summary
    Get-Item .\WSFA,
        .\Q_numbers,
        .\Supreme_Court,
        .\WPA,
        .\WWI_cards,
        .\Audiovisual,
        .\Executive_orders -Force | out-321preservationreport.ps1 -Attn -Candidates -Summary
} -Loop
