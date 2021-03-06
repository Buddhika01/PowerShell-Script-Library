import-module WebAdministration
$app_title = "Sitecore v6.5 Hardening Script"
$version = 0.1

$a = (Get-Host).UI.RawUI
$a.WindowTitle = "$app_title v" + $version
$a.ForegroundColor = "yellow"

$sites = dir IIS:\sites\*
Set-Variable selectedSite "unknown" -scope global
Set-Variable selectedSiteId 0 -scope global
$cpu = if($env:Processor_Architecture -eq "x86"){"x86"}else{"x64"}

$handlers = Get-Webconfiguration system.webServer/handlers/* 'IIS:\sites\discover' -Recurse | select *

function header()
{
    Clear-Host
    $a.ForegroundColor = "yellow"
    Write-Host "+================================================+"
    Write-Host "|    :[ " -nonewline
    Write-Host $app_title v$version -nonewline -foregroundcolor white
    Write-Host " ]:   |" -foregroundcolor yellow
    Write-Host "+================================================+"
}

function footer()
{
    Write-Host "+================================================+" -foregroundcolor yellow
}

function printValue()
{
    param([string]$name, [string]$value, [bool]$fancy)
    Write-Host "| " -nonewline
    
    if($value)
    {
        Write-Host $name -nonewline -foregroundcolor white
        Write-Host " : [ " -nonewline -foregroundcolor yellow
        if($fancy)
        {
            fancyDisplay $value
        }
        else{
            Write-Host $value -nonewline -foregroundcolor cyan
        }
        Write-Host " ]" -foregroundcolor yellow
    }else{
        Write-Host $name -foregroundcolor white
    }  
}

function spinnerDisplay() 
{
    $saveY = [console]::CursorTop
    $saveX = [console]::CursorLeft   
    $str = '\','|','/','-'     
    $str | ForEach-Object { Write-Host -Object $_ -NoNewline
            Start-Sleep -Milliseconds 30
            [console]::setcursorposition($saveX,$saveY)
            } # end foreach-object
}

function fancyDisplay() 
{
    param([string]$text)
    $saveY = [console]::CursorTop
    $saveX = [console]::CursorLeft       
    $text.ToCharArray() | ForEach-Object { 
            $saveX++
            Write-Host -Object "$_" -NoNewline -foregroundcolor cyan
            spinnerDisplay
            #Start-Sleep -Milliseconds 50
            [console]::setcursorposition($saveX,$saveY)
            } # end foreach-object
}

function printOption()
{
    param([int]$number, [string]$name)
    Write-Host "| [" -nonewline -foregroundcolor yellow; Write-Host $number -foregroundcolor white -nonewline; Write-Host "] " -foregroundcolor yellow -nonewline; Write-Host $name -foregroundcolor cyan
}

function siteSelect()
{
    header
    Write-Host "| " -nonewline
    Write-Host "Select Site:" -nonewline -foregroundcolor white
    Write-Host "                              |" -foregroundcolor yellow
    footer
    $count = 0                                  
    $sites | ForEach-Object { $count++; printOption $count $_.name }
    footer
    
    $a.ForegroundColor = "white"
    $input = Read-Host "Select [1-$count]"
    #TODO: Do some validation of the input !
    $global:selectedSite = $sites[($input-1)].name
    $global:selectedSiteId = ($input-1)
}

function fullHeader()
{
    $site =  $sites[$selectedSiteId]
    $app_pool_name = $site.applicationPool
    $app_pool = Get-Item IIS:\appPools\$app_pool_name

    header
    printValue "Site    " $selectedSite
    printValue "AppPool " $app_pool_name
    printValue "RunTime " $app_pool.managedRuntimeVersion
    printValue "Pipeline" $app_pool.managedPipelineMode
    printValue "CPU     " $cpu
    footer     
}

function optionSelect
{
    fullHeader
    printValue "Please select.."
    footer
    printOption 1 "Create backup of web.config." 
    printOption 2 "Limit access to *.xml/*.xslt/*.mrt files."
    printOption 3 "Disable anonymous access."
    printOption 4 "Turn off login autocomplete"
    printOption 5 "Deny execute on upload folder"
    printOption 6 "Disable 'uploadwatcher'"
    printOption 0 "Quit"
    footer
    $a.ForegroundColor = "white"    
}

function returnMenu($option)
{
    Clear-Host;
    fullheader;
    Write-Host "You chose option $option";
    Write-Host "Press any key to return to the main menu.";
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown"); 
}

function limitAccess($option)
{
    $site =  $sites[$selectedSiteId]
    $app_pool_name = $site.applicationPool
    $app_pool = Get-Item IIS:\appPools\$app_pool_name

    Clear-Host;
    header;
    printValue "Limit access to *.xml/*.xslt/*.mrt files."
    footer
    printValue "CPU Mode:            " $cpu
    printValue "NET Version:         " $app_pool.managedRuntimeVersion
    
    Write-Host "| " -nonewline
    Write-Host "Adding handlers..    " -nonewline -foregroundcolor white
    Write-Host " : [ " -nonewline -foregroundcolor yellow
    
    $config = Get-WebConfiguration /system.webServer/handlers/* "IIS:\sites\$selectedSite"
    $sectionCount = [int]($config.count)
       
    $job = Start-Job -Name "handlerJob" -ArgumentList "$selectedSite","$sectionCount" -ScriptBlock {
        import-module WebAdministration
        $selectedSite = $args[0]
        $sectionCount = $args[1]
        
        Add-WebConfiguration /system.webServer/handlers "IIS:\sites\$selectedSite" -AtIndex $sectionCount -Value @{path="*.mrt";verb="*";type="System.Web.HttpForbiddenHandler";name="mrt (integrated)";preCondition="integratedMode"}
        Add-WebConfiguration /system.webServer/handlers "IIS:\sites\$selectedSite" -AtIndex $sectionCount -Value @{path="*.config.xml";verb="*";type="System.Web.HttpForbiddenHandler";name="config.xml (integrated)";preCondition="integratedMode"}
        Add-WebConfiguration /system.webServer/handlers "IIS:\sites\$selectedSite" -AtIndex $sectionCount -Value @{path="*.xslt";verb="*";type="System.Web.HttpForbiddenHandler";name="xslt (integrated)";preCondition="integratedMode"}
        Add-WebConfiguration /system.webServer/handlers "IIS:\sites\$selectedSite" -AtIndex $sectionCount -Value @{path="*.xml";verb="*";type="System.Web.HttpForbiddenHandler";name="xml (integrated)";preCondition="integratedMode"}
        Add-WebConfiguration /system.webServer/handlers "IIS:\sites\$selectedSite" -AtIndex $sectionCount -Value @{path="*.mrt";name="mrt handler (classic)";verb="*";modules="IsapiModule";scriptProcessor="%windir%\Microsoft.NET\Framework\v2.0.50727\aspnet_isapi.dll";resourceType="Unspecified";preCondition="classicMode,runtimeVersionv2.0"}
        Add-WebConfiguration /system.webServer/handlers "IIS:\sites\$selectedSite" -AtIndex $sectionCount -Value @{path="*.config.xml";name="config.xml handler (classic)";verb="*";modules="IsapiModule";scriptProcessor="%windir%\Microsoft.NET\Framework\v2.0.50727\aspnet_isapi.dll";resourceType="Unspecified";preCondition="classicMode,runtimeVersionv2.0"}
        Add-WebConfiguration /system.webServer/handlers "IIS:\sites\$selectedSite" -AtIndex $sectionCount -Value @{path="*.xslt";name="xslt Handler (classic)";verb="*";modules="IsapiModule";scriptProcessor="%windir%\Microsoft.NET\Framework\v2.0.50727\aspnet_isapi.dll";resourceType="Unspecified";preCondition="classicMode,runtimeVersionv2.0"}
        Add-WebConfiguration /system.webServer/handlers "IIS:\sites\$selectedSite" -AtIndex $sectionCount -Value @{path="*.xml";name="xml Handler (classic)";verb="*";modules="IsapiModule";scriptProcessor="%windir%\Microsoft.NET\Framework\v2.0.50727\aspnet_isapi.dll";resourceType="Unspecified";preCondition="classicMode,runtimeVersionv2.0"}
    }
       
    myWaitJob("handlerJob")
        
    fancyDisplay "COMPLETE"
    Write-Host " ]" -foregroundcolor yellow
    
    remove-job *
       
    Write-Host "| " -nonewline
    Write-Host "Adding httpHandlers.." -nonewline -foregroundcolor white
    Write-Host " : [ " -nonewline -foregroundcolor yellow
    
    $config = Get-WebConfiguration /system.web/httpHandlers/* "IIS:\sites\$selectedSite"
    $sectionCount = [int]($config.count)
       
    $job = Start-Job -Name "httpHandlerJob" -ArgumentList "$selectedSite","$sectionCount" -ScriptBlock {
        import-module WebAdministration
        $selectedSite = $args[0]
        $sectionCount = $args[1]
        Add-WebConfiguration /system.web/httpHandlers "IIS:\sites\$selectedSite" -AtIndex $sectionCount -Value @{path="*.mrt";verb="*";type="System.Web.HttpForbiddenHandler";validate="true"}
        Add-WebConfiguration /system.web/httpHandlers "IIS:\sites\$selectedSite" -AtIndex $sectionCount -Value @{path="*.config.xml";verb="*";type="System.Web.HttpForbiddenHandler";validate="true"}
        Add-WebConfiguration /system.web/httpHandlers "IIS:\sites\$selectedSite" -AtIndex $sectionCount -Value @{path="*.xslt";verb="*";type="System.Web.HttpForbiddenHandler";validate="true"}
        Add-WebConfiguration /system.web/httpHandlers "IIS:\sites\$selectedSite" -AtIndex $sectionCount -Value @{path="*.xml";verb="*";type="System.Web.HttpForbiddenHandler";validate="true"}
    }
    
    myWaitJob("httpHandlerJob")
    
    fancyDisplay "COMPLETE"
    Write-Host " ]" -foregroundcolor yellow
    
    remove-job *
    
    footer
    Write-Host "Press any key to return to the main menu.";
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown");
    footer; 
}

function myWaitJob($job) {
    $saveY = [console]::CursorTop
    $saveX = [console]::CursorLeft   
    $str = '|','/','-','\'     
    do {
    $str | ForEach-Object { Write-Host -Object $_ -NoNewline
            Start-Sleep -Milliseconds 100
            [console]::setcursorposition($saveX,$saveY)
            }
        if ((Get-Job -Name $job).state -eq 'Running') 
        {$running = $true}
        else {$running = $false}
        }
    while ($running)
}

function backupConfig($option)
{
    $site =  $sites[$selectedSiteId]
    $currentDate = (get-date).tostring("yyyyMMddhhmmss")
    $filename_orig = $site.physicalPath +"\web.config"
    $filename = $site.physicalPath +"\web.config.$currentDate"
    
    Clear-Host;
    header;
    printValue "Backing up web.config.."
    footer
    printValue "Original" "$filename_orig"
    printValue "Backup  " "$filename"
    Copy-Item -LiteralPath $filename_orig $filename
    printValue "Status  " "COMPLETE" $true
    footer 

    Write-Host "Press any key to return to the main menu.";
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown");
    footer;
}

function removeAnon($option)
{
    header
    printValue "Disable 'anonymous' access.."
    footer
    
    Write-Host "| " -nonewline
    Write-Host "/App_Config..               " -nonewline -foregroundcolor white
    Write-Host " : [ " -nonewline -foregroundcolor yellow

    Set-WebConfigurationProperty -filter /system.WebServer/security/authentication/AnonymousAuthentication -PSPath IIS:\ -name enabled -location "$selectedSite/App_Config" -value false
    
    fancyDisplay "COMPLETE"
    Write-Host " ]" -foregroundcolor yellow
    
    Write-Host "| " -nonewline
    Write-Host "/sitecore/admin..           " -nonewline -foregroundcolor white
    Write-Host " : [ " -nonewline -foregroundcolor yellow
    
    Set-WebConfigurationProperty -filter /system.WebServer/security/authentication/AnonymousAuthentication -PSPath IIS:\ -name enabled -location "$selectedSite/sitecore/admin" -value false
    
    fancyDisplay "COMPLETE"
    Write-Host " ]" -foregroundcolor yellow
    
    Write-Host "| " -nonewline
    Write-Host "/sitecore/debug..           " -nonewline -foregroundcolor white
    Write-Host " : [ " -nonewline -foregroundcolor yellow
    
    Set-WebConfigurationProperty -filter /system.WebServer/security/authentication/AnonymousAuthentication -PSPath IIS:\ -name enabled -location "$selectedSite/sitecore/debug" -value false
    
    fancyDisplay "COMPLETE"
    Write-Host " ]" -foregroundcolor yellow
    
    Write-Host "| " -nonewline
    Write-Host "/sitecore/shell/WebService.." -nonewline -foregroundcolor white
    Write-Host " : [ " -nonewline -foregroundcolor yellow
    
    Set-WebConfigurationProperty -filter /system.WebServer/security/authentication/AnonymousAuthentication -PSPath IIS:\ -name enabled -location "$selectedSite/sitecore/shell/WebService" -value false

    fancyDisplay "COMPLETE"
    Write-Host " ]" -foregroundcolor yellow
    footer
   
    Write-Host "Press any key to return to the main menu.";
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown");
    footer;
}

function aboutMenu($option)
{
	Clear-Host
	Write-Host "           _____  " -NoNewline -ForegroundColor White
	Write-Host ".    " -NoNewline -ForegroundColor cyan
	Write-Host "___" -NoNewline -ForegroundColor White
	Write-Host "         .         .        .                .    " -ForegroundColor cyan              
	Write-Host "      ____/    /__)\__/  /_  ______)\ _______)\ ______)\________  _____)\   "               
	Write-Host "   __/__ .____/    /    __/_/    ___//   _    /   _    /   _  __)/   ___/__ "               
	Write-Host "__/     |    /    /    /    /   __/  /  |/___/   |/   /   |/    \   __/   / "               
	Write-Host "\      _____/\___/\___     /____    /___    /________/___ /     /___     /  "               
	Write-Host " \____/" -NoNewline
	Write-Host "===============" -NoNewline -ForegroundColor Yellow
	Write-Host "(___/" -NoNewline -ForegroundColor White
	Write-Host "===" -NoNewline -ForegroundColor Yellow
	Write-Host "(____/" -NoNewline -ForegroundColor White
	Write-Host "===" -NoNewline -ForegroundColor Yellow
	Write-Host "(___/" -NoNewline -ForegroundColor White
	Write-Host "=============" -NoNewline -ForegroundColor Yellow
	Write-Host "(_____/" -NoNewline -ForegroundColor White
	Write-Host "===" -NoNewline -ForegroundColor Yellow
	Write-Host "(____/" -NoNewline -ForegroundColor White
	Write-Host "=--" -ForegroundColor Yellow
	Write-Host "+==========================================================================+"
	Write-Host "|                :[ " -nonewline
	Write-Host $app_title v$version -nonewline -foregroundcolor cyan
	Write-Host " ]:                 |" -foregroundcolor white
	Write-Host "+===============================================================/\=========+"
	printValue "Version  " "v$version" $true
	printValue "Coded By " "Stephen Pope" $true
	printValue "Contact  " "stp@sitecore.net" $true
	Write-Host "+=====================================================================\/===+"

	Write-Host "Press any key to return to the main menu.";
	$key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown");
}

function turnOffAuto($option)
{
	header
	printValue "Disable autocomplete.."
	footer
	$path =  $sites[$selectedSiteId].physicalPath + "\sitecore\login\default.aspx"
	
	Write-Host "| " -nonewline
    Write-Host "Updating.." -nonewline -foregroundcolor white
    Write-Host " : [ " -nonewline -foregroundcolor yellow

	(Get-Content $path) | 
	Foreach-Object { $_ -replace '<form id="LoginForm" runat="server">', '<form id="LoginForm" runat="server" autocomplete="off">' } | 
	Set-Content $path

	fancyDisplay "COMPLETE"
    Write-Host " ]" -foregroundcolor yellow
	footer
	
	Write-Host "Press any key to return to the main menu.";
	$key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown");
}

function disableExecute($option)
{
	header
	printValue "Deny 'execute' on upload folder.."
	footer
	
	Write-Host "| " -nonewline
    Write-Host "Updating.." -nonewline -foregroundcolor white
    Write-Host " : [ " -nonewline -foregroundcolor yellow

	Set-WebConfigurationProperty /system.WebServer/handlers "IIS:\sites\$selectedSite/upload" -Name accessPolicy -value "Read"

	fancyDisplay "COMPLETE"
    Write-Host " ]" -foregroundcolor yellow
	footer

	Write-Host "Press any key to return to the main menu.";
	$key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown");
}

function disableUploadwatcher($option)
{
	header
	printValue "Disable 'uploadwatcher'.."
	footer
	
	Write-Host "| " -nonewline
    Write-Host "system.webServer.." -nonewline -foregroundcolor white
    Write-Host " : [ " -nonewline -foregroundcolor yellow
	
	#Remove-WebManagedModule -Name SitecoreUploadWatcher -PSPath "IIS:\sites\$selectedSite"
	
	Remove-WebConfigurationProperty -PSPath "IIS:\sites\$selectedSite" -Name Collection -Filter /system.webServer/modules -AtElement @{name="SitecoreUploadWatcher"}
	
	fancyDisplay "COMPLETE"
    Write-Host " ]" -foregroundcolor yellow
	
	Write-Host "| " -nonewline
    Write-Host "system.web.." -nonewline -foregroundcolor white
    Write-Host " : [ " -nonewline -foregroundcolor yellow
	
	Remove-WebConfigurationProperty -PSPath "IIS:\sites\$selectedSite" -Name Collection -Filter /system.web/httpModules -AtElement @{name="SitecoreUploadWatcher"}
	
	fancyDisplay "COMPLETE"
    Write-Host " ]" -foregroundcolor yellow
	footer
	
	Write-Host "Press any key to return to the main menu.";
	$key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown");
}

#Main section ..
siteSelect
do 
{ 
    optionSelect;
    $action = Read-Host "Select [1-6 or 0]"
    switch ($action) 
    {
        "1" { backupConfig $action; } 
        "2" { limitAccess $action; }
        "3" { removeAnon $action; }
        "4" { turnOffAuto $action; }
        "5" { disableExecute $action; }
        "6" { disableUploadwatcher $action; }
		"99" { aboutMenu $action; }
        "0" { }
        default 
        { 
            Clear-Host;
            Write-Host "Invalid input. Please enter a valid option. Press any key to continue.";
            $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown");
        }
    }   
} until ($action -eq "0");