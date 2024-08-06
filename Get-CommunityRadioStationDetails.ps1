<#
  .SYNOPSIS
  Downloads community radio station details to csv.

  .DESCRIPTION
  The RH_UnifiedRS.ps1 script scrapes up to three websites (depending on the option chosen) to extract the details of the Community, 
  Digital and Small Scale Radio Stations and save them to headed CSV files. If there are any errors during the extraction, these errors will be
  saved with the same name, in the same folder but with an "Error-" prefix and a TXT suffix.

  .OUTPUTS
  CSV file(s). Depending on the option chosen, up to 3 csv files, and 3 error files (as txt documents) will be created. 
  By default, the three files will be created in the folder that the script is running from, but you can choose an output folder if you would like 

  .EXAMPLE
  PS> .\RH_UnifiedRS.ps1 # Saves the CSV and TXT file(s) in the current script folder.

  .NOTES
  Author: Pierre de Wet
  Date:   August 2, 2024
#>


# Helper functions
function Show-Menu {

    param (
        [string]$Title = 'Download Radio Station Details'
    )
    write-host "`n"
    Write-Host "========= $Title ==========="
    Write-Host "=  1: Press '1' to download Community stations.    ="
    Write-Host "=  2: Press '2' to download Digital stations.      ="
    Write-Host "=  3: Press '3' to download Small-scale stations.  ="
    Write-Host "=  4: Press '4' to download ALL station data.      ="
    Write-Host "=  Q: Press 'Q' to quit.                           ="
    Write-Host "===================================================="

    $selection = Read-Host "Please choose stations to scrape"
    
    if ($selection -ne 'q') {
        $outputSaveLoc = Get-OutputDirectory
    }

    switch ($selection) {
        '1' { 
            Get-LinkData "CommunityRadio" $community_details.Base_url $community_details.Station_home_url $community_details.Station_details_regex $community_details.Station_name_regex $community_details.Link_match $outputSaveLoc
        }
        '2' { 
            Get-LinkData "CommunityDigitalRadio" $digital_details.Base_url $digital_details.Station_home_url $digital_details.Station_details_regex $digital_details.Station_name_regex $digital_details.Link_match $outputSaveLoc
        }
        '3' { 
            Get-LinkData "CommunitySmallScaleRadio" $smallscale_details.Base_url $smallscale_details.Station_home_url $smallscale_details.Station_details_regex $smallscale_details.Station_name_regex $smallscale_details.Link_match $outputSaveLoc
        }
        '4' { 
            Get-LinkData "CommunityRadio" $community_details.Base_url $community_details.Station_home_url $community_details.Station_details_regex $community_details.Station_name_regex $community_details.Link_match $outputSaveLoc
            Get-LinkData "CommunityDigitalRadio" $digital_details.Base_url $digital_details.Station_home_url $digital_details.Station_details_regex $digital_details.Station_name_regex $digital_details.Link_match $outputSaveLoc
            Get-LinkData "CommunitySmallScaleRadio" $smallscale_details.Base_url $smallscale_details.Station_home_url $smallscale_details.Station_details_regex $smallscale_details.Station_name_regex $smallscale_details.Link_match $outputSaveLoc
        }
        'q' { return }  # Quit the menu
    }
    # Recurse until Q is pressed
    Show-Menu
}

Function Write-ProgressBar {
	param (
		[int]$counter=1,
		[int]$total=100,
		[string]$activity
	)
	$percent_complete = ($counter/$total) * 100
	Write-Progress -Activity $activity -Status " $percent_complete% Complete:" -PercentComplete $percent_complete
	# Start-Sleep -Milliseconds 10
}

Function Get-SiteLinks {
    param (
        [string]$baseURL
    )
    Write-Host "Attempting to scrape: $baseURL"

    try {
        $scraped_links = (Invoke-WebRequest -Uri $baseURL).Links.Href  | Get-Unique
    } catch {
        $StatusCode = $_.Exception.Response.StatusCode
        if ($StatusCode -eq [system.net.HttpStatusCode]::NotFound) {
            Write-Error "The Radio Page was not found at the URL"
        } else {
            Write-Error "Expected 200, got $([int]$StatusCode)"
        }
    }
    return $scraped_links
    Write-Host "Scrape successful..."
}

Function Get-OutputDirectory {

    Write-Host "`n"
    Write-Host "By default, the files will be saved in the same directory as where the script is running from."
    Write-Host "If you would like to save the files in a different directory, enter it below."
    $OutputLocation = Read-Host "Choose save directory. (Enter to select default)"

    if (![string]::IsNullOrEmpty($OutputLocation)) {       
        if (Test-Path $OutputLocation) {
            Write-Host "The entered directory path exists. The script will attempt to save the output file(s) there..."
            return $OutputLocation
        }
        else {
            # The custom output folder doesn't exist
            return $PSScriptRoot
            Write-Host "The entered directory path doesn't exist. `nThe script will attempt to save the output file(s) to the default location instead: $PSScriptRoot"
        }
    }
    else {
        return $PSScriptRoot
    }
}

Function Write-OutFile {
    param (
        [string]$fileName,
        [System.Collections.ArrayList]$fileData,
        [string]$errorName,
        [System.Collections.Generic.List[string]]$errorData,
        [string]$OutputDirectory = "$PSScriptRoot"
    )
    
    Write-Host "Attempting to save data file(s)..."

    $errorfilename = Join-Path -Path $OutputDirectory -ChildPath "$errorName-$(Get-Date -Format 'yyMMdd-HHmm').txt"
    $workfilename  = Join-Path -Path $OutputDirectory -ChildPath "$fileName-$(Get-Date -Format 'yyMMdd-HHmm').csv"
    
    try 
    {
        $errorData | Out-File -Path  $errorfilename -ErrorAction Stop
        $fileData | Export-Csv -Path $workfilename  -NoTypeInformation -ErrorAction Stop
    } catch [System.IO.FileNotFoundException]
    {
        Write-Output "Could not find file path"
    }
    catch [System.IO.IOException]
    {
            Write-Output "IO error with the file"
    }
    
    Write-Host "Output file(s) saved in '$OutputDirectory' directory..."
}

Function Get-LinkData {
    param (
        [string]$name,
        [string]$baseURL,
        [string]$homeURL,
        [string]$stationrgx,
        [string]$titlergx,
        [string]$prefixrgx,
        [string]$outputfolder = "$PSScriptRoot"
    )  

    Write-Host "STARTING TO PROCESS: $name"
    
    $scraped_links = Get-SiteLinks $baseURL

    [System.Collections.ArrayList]$station_data = @()
    [System.Collections.Generic.List[string]]$error_data = @()
    $radio_links = [System.Collections.ArrayList]::new()

    Write-Host "Cleaning up the $name homepage and extracting links for the radio stations..."
    
    # Clean up links - Only include radio station URLS and remove any other links in the page data
    $link_counter=1
    foreach ($link in $scraped_links) {
        if ($link -match $prefixrgx) {
            [void]$radio_links.Add($link)
        }
        $link_counter++
    }
        
    Write-Host "Processing $($radio_links.Count) $name station links. This may take quite some time."
    $station_count=1
    foreach ($station_link in $radio_links) {
        Write-ProgressBar $station_count $radio_links.Count "Processing $name Station Details: "
        try {
            $station_html = Invoke-RestMethod "$($homeURL)$station_link"
        } catch {
            $StatusCode = $_.Exception.Response.StatusCode
            if ($StatusCode -eq [system.net.HttpStatusCode]::NotFound) {
                Write-Error "The Radio Page was not found at the URL: $($homeURL)$station_link"            
            } else {
                Write-Error "Expected 200, got $([int]$StatusCode)"
            }
        }
    
        $all_matches = ($station_html | Select-String $stationrgx -AllMatches).Matches
        $title = ($station_html | Select-String $titlergx -AllMatches).Matches    
    
        if (![string]::IsNullOrEmpty($title)) {
            $radio_details =[PSCustomObject]@{
                'Name' = ($title.Groups.Where{$_.Name -like 'name'}).Value
                'Licence Number' = ($all_matches.Groups.Where{$_.Name -like 'licence_no'}).Value
                'Contact Details' = ($all_matches.Groups.Where{$_.Name -like 'contact'}).Value.Replace('</p><p>',' ').Replace('</p>','')
                'Telephone' = ($all_matches.Groups.Where{$_.Name -like 'phone'}).Value
                'Website' = ($all_matches.Groups.Where{$_.Name -like 'website'}).Value
                'Email' = ($all_matches.Groups.Where{$_.Name -like 'email'}).Value
            }
            switch ($name) {
                "CommunityRadio" {	
                    $radio_details | Add-Member -MemberType NoteProperty -Name "Frequency" -Value ($all_matches.Groups.Where{$_.Name -like 'frequency'}).Value.Replace('</p><p>',' ').Replace('</p>','')
                    $radio_details | Add-Member -MemberType NoteProperty -Name "Airing From" -Value ($all_matches.Groups.Where{$_.Name -like 'air_from'}).Value
                    $radio_details | Add-Member -MemberType NoteProperty -Name "Airing To" -Value ($all_matches.Groups.Where{$_.Name -like 'air_to'}).Value
                    $radio_details | Add-Member -MemberType NoteProperty -Name "Licencee" -Value ($all_matches.Groups.Where{$_.Name -like 'licencee'}).Value
                    $radio_details | Add-Member -MemberType NoteProperty -Name "Group" -Value ($all_matches.Groups.Where{$_.Name -like 'group'}).Value
                }
                "CommunityDigitalRadio" {
                    $radio_details | Add-Member -MemberType NoteProperty -Name "SSDAB multiplex" -Value ($all_matches.Groups.Where{$_.Name -like 'ssdab'}).Value   
                }
                "CommunitySmallScaleRadio" {
                    $radio_details | Add-Member -MemberType NoteProperty -Name "Frequency" -Value ($all_matches.Groups.Where{$_.Name -like 'freq'}).Value.Replace('</p><p>',', ') 
                    $radio_details | Add-Member -MemberType NoteProperty -Name "Licensee" -Value ($all_matches.Groups.Where{$_.Name -like 'Licensee'}).Value
                }
                default {
                    Write-Host "Unknown Radio Station: $name"
                    Write-Host "Ending..."
                    Exit
                }
            }
            # use void to not return a value when an item is added to an arraylist - In future test changing to a list type
            [void]$station_data.Add($radio_details)
        }
        else {
            # use void to not return a value when an item is added to an arraylist - In future test changing to a list type
            [void]$error_data.Add("No URL at $($homeURL)$station_link")
        }
        $station_count++
    }    
 
    Write-Host "Completed processing: $name"

    Write-OutFile $name $station_data "Error-$name" $error_data $outputfolder
}

$community_details =[PSCustomObject]@{
    Station_name_regex      = '<h1>(?<name>.*)</h1>'
    Station_details_regex   = '<div class="skin">\s*?<div class="body">\s*?<p>(\s*?|.*)</p>\s*?<br />\s*?<p>(?<frequency>.*?)</p>\s*?<p>(.|\n)*? On Air From:(?<air_from>.*?)</p>\s*?<p>(.|\n)*to:(?<air_to>.*?)</p>\s*?<p>(.|\n)*Licensee:(?<licencee>.*?)</p>\s*?(<p>\s*?Contact Details:(?<contact>.*?)</p>)?\s*?<p>\s*?Telephone:(?<phone>.*?)</p>\s*?<p>\s*?Website:(?<website>.*?)</p>\s*?<p>\s*?Email:(?<email>.*?)</p>\s*?<p>\s*?Group:(?<group>.*?)</p>\s*?<p>\s*?Licence Number:(?<licence_no>.*?)</p>'
    Link_match              = '^cr'
    Base_url                = 'http://static.ofcom.org.uk/static/radiolicensing/html/radio-stations/community/community-main.htm'
    Station_home_url        = 'http://static.ofcom.org.uk/static/radiolicensing/html/radio-stations/community/'
}

$digital_details =[PSCustomObject]@{
    Station_name_regex      = '<h1>(?<name>.*)</h1>'
    Station_details_regex   = '<div class="skin">\s*?<div class="body">\s*?<p>\s*?Licensee: (?<licensee>.*?)</p><p>SSDAB multiplex: (?<ssdab>.*?)</p>\s*?(<p>\s*?Contact Details:(?<contact>.*?)</p>)?\s*?<p>Telephone :(?<phone>.*?)</p><p>Website: (?<website>.*?)</p><p>Email: (?<email>.*?)</p><p>Licence Number: (?<licence_no>.*?)</p>'
    Link_match              = '^cdp'
    Base_url                = 'https://static.ofcom.org.uk/static/radiolicensing/html/radio-stations/communuitydigital/communuitydigitalsoundprogram-main.htm'
    Station_home_url        = 'https://static.ofcom.org.uk/static/radiolicensing/html/radio-stations/communuitydigital/'
}

$smallscale_details =[PSCustomObject]@{
    Station_name_regex      = '<h1>(?<name>.*)</h1>'
    Station_details_regex   = '<div class="skin">\s*?<div class="body">\s*?<p>\s*?Licence Name: (?<licence_name>.*?)</p><p>Licence Number: (?<licence_no>.*?)</p>\s*?(<p>\s*?(?<freq>.*?)</p>)?\s*?<p>Licensee: (?<licensee>.*?)</p>\s*?(<p>\s*?Contact Details:(?<contact>.*?)</p>)?\s*?<p>Telephone :(?<phone>.*?)</p><p>Website: (?<website>.*?)</p><p>Email: (?<email>.*?)</p>'
    Link_match              = '^ds'
    Base_url                = 'https://static.ofcom.org.uk/static/radiolicensing/html/radio-stations/smallscaledigital/smallscaledigital-main.htm'
    Station_home_url        = 'https://static.ofcom.org.uk/static/radiolicensing/html/radio-stations/smallscaledigital/'
}

# Script Entry Point below
# Process the stations
Show-Menu 