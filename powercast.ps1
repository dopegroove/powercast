Param(
  [string]$Mode,
  [string]$mediaPath
)

# Do I need this function.. probably not...
function createPath ($path){cmd /c md $path}

Function deleteFeed{
write-host "Deleting Feeds..."
}

$maxOldPodcasts = 3
$maxJobs =3
$MyOPMLFile= "c:\u\subscriptions.opml" #change this to the name of your OPML file
if ($mediaPath -eq "") {$mediaPath = "c:\dump\podcasts"}
$podcastHistory ="$mediaPath\podcastHistory.txt"
$currentPath = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
$debugFlag = 0

Function getFeeds{
write-host "Getting Feeds from $MyOPMLFile." -foregroundcolor white
write-host "Files will be downloaded to: $mediaPath." -foregroundcolor white
#pull in OPML Feed 
[xml]$opml= Get-Content $MyOPMLFile
$podcastList = $opml.opml.body.outline
foreach ($item in $podcastList){
$podcastTitle = $item.text|out-string
$podcastTitle = $podcastTitle.trim()
$rssLink = $item.xmlUrl|out-string
#Test URL to see if it is up
if ($debugFlag -gt 0){"Testing URL: $rssLink"}
Try {$HTTP_Request = [System.Net.WebRequest]::Create($rssLink)
$HTTP_Response = $HTTP_Request.GetResponse()
$HTTP_Status = [int]$HTTP_Response.StatusCode}
Catch {$HTTP_Status = 404} 
$HTTP_Response.Close()
if (($HTTP_Status -eq 200)) {
$linkDump = ([xml](new-object net.webclient).downloadstring($rssLink))
#Get Feed info / Fix Podcast Title
$podcastTitle = $linkDump.rss.channel.title|out-string
$podcastTitle= $podcastTitle.trim()
$podcastTitle = $podcastTitle -replace '[^A-Za-z0-9_. !\\-]+', ""
if ($podcastTitle -ne ""){
write-host "----Checking the $podcastTitle Feed---" -foregroundcolor Cyan
#pull in the latest podcasts from the feed
$podcasts= @{}
$podcasts = $linkDump.rss.channel.item
$podcasts = $podcasts|select title, enclosure, content, @{Name="pubdate";Expression={get-date ($_.pubdate) -format "yyyy/MM/dd hh:mm"}}
$podcasts = $podcasts|sort pubdate -Descending|select -first $maxOldPodcasts

foreach ($podcast in $podcasts){
    $episodeTitle= $podcast.title
    $podcastUrl = @{}
    #skip if no enclosure for feed 
    if ($podcast.enclosure){
    if ($debugFlag -gt 0) {write-output $podcast.enclosure|fl}
    $podcastUrl = New-Object System.Uri($podcast.enclosure.url)
    $mediaFileName = $podcastUrl.Segments[-1]
    $dlpath = "$mediaPath\$podcastTitle"
    $dlpath= $dlpath.trim()
    $mediaFilePath = "$dlpath\$mediaFileName"
    if (!(test-path $dlpath)){createPath $dlpath}
    #Skip if file was downloaded in the past or if exists in the folder
    $skipFile = 0
	
	#check history file to see if the file was downloaded before 
	if (test-path $podcastHistory){
	$oldPodcasts = import-csv $podcastHistory -delimiter ";" -Header podcast,media
	$arraydump = $oldPodcasts|select podcast,media|?{$_.media -eq "$mediaFileName"}|?{$_.podcast -eq "$podcastTitle"}
	if ($arraydump) {write-host "File found in history file" -foregroundcolor white
	$skipFile = 1}
	}
	
	#Skip the file if it is in the folder
    if ($skipFile -eq 0){	
    if (test-path $mediaFilePath) {
	#update podcast history file
	$strdump = "$podcastTitle;$mediaFileName"
	$strdump|out-file $podcastHistory -append -NoClobber
	$skipFile = 1}
	}
	
    if ($skipFile -eq 0)
    {
	write-host "Downloading $episodeTitle ($mediaFileName)" -foregroundcolor green
    start-job -scriptblock {Invoke-WebRequest $using:podcastUrl -Method Get -OutFile $using:mediaFilePath -UserAgent FireFox}
    } else {write-host "Skipping $mediaFileName. Already Got it..." -foregroundcolor white}
    } Else {write-host "No Podcast Media found for this post!" -foregroundcolor red
    if ($debugFlag -gt 1){
    $podcasts = $linkDump.rss.channel.item
    write-output $podcasts|fl
    write-output $podcast.content|fl}
    }
    }
write-host "----End of $podcastTitle Feed---" -foregroundcolor Cyan

#wait for a bit if there are a number of podcasts downloading
   $waitFlag = 1 
   do {
  $downloads = get-Job |where {$_.State -eq 'Running'}
  if ($debugFlag -gt 1){Write-output $downloads|ft}
  $inprogess = $downloads|Measure-Object name
  if ($inprogess.count -gt $maxJobs ){
  $downloadcount = $inprogess.count
  write-host "Waiting for some downloads to complete... ($downloadcount)" -foregroundcolor yellow
  $waitFlag = 0
  start-sleep -s 45
  } else {$waitFlag = 1}
  }while ($waitFlag -eq 0)
}
}Else {write-host "The website for $podcastTitle appears to be down..." -foregroundcolor red}
} 

#Wait for all jobs to complete
$waitFlag = 1 
   do {
  $downloads = get-Job |where {$_.State -eq 'Running'}
  $inprogess = $downloads|Measure-Object name
  if ($inprogess.count -gt 0 ){
  $downloadcount = $inprogess.count
  write-host "Waiting for some downloads to complete... ($downloadcount)" -foregroundcolor yellow
  Write-output $downloads|ft
  $waitFlag = 0
  start-sleep -s 45
  } else {$waitFlag = 1}
  }while ($waitFlag -eq 0)

#clean up completed jobs
Get-Job|where {$_.state -eq "Completed"}|Remove-Job
}

#run according to mode 
write-host "Powercast V0 - Mode: $mode" -foregroundcolor Yellow
switch ($mode){
"download" {getFeeds}
"delete"{deleteFeeds}
}