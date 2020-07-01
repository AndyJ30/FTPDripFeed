#Set server name, user, password and directory
$server = 'ftp://ftp.example.com/'
$username = 'user'
$password = 'pass'
$remoteDirectory ='uploads'
$localDirectory = 'C:\My\Local\Directory'
    
$batchSize = 10   #How many files to upload at once.
$maxFTPFiles = 1  #Dont upload any files if there are more than this many already in the FTP directory.
$FTPPollRate = 10 #How long to wait (seconds) before checking again if there were too many files in the FTP directory.

#Function to upload a file to an FTP directory
Function Upload-FTPFile{
    Param(
     [System.Uri]$server,
     [string]$username,
     [string]$password,
     [string]$directory,
     [System.IO.FileInfo]$file
    )

    $uri =  "$server$directory/$file"

    $fileContent = [System.IO.File]::ReadAllBytes($file.FullName)

    try{     
        $FTPRequest = [System.Net.FtpWebRequest]::Create($uri)
        $FTPRequest = [System.Net.FtpWebRequest]$FTPRequest
        $FTPRequest.Credentials = New-Object System.Net.NetworkCredential($username, $password)
        $FTPRequest.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
        $FTPRequest.UseBinary = $true
        $FTPRequest.UsePassive = $true
        $FTPRequest.ContentLength = $fileContent.Length
      
        $requestStream = $FTPRequest.GetRequestStream()
        $requestStream.Write($fileContent, 0, $fileContent.Length)
    }
    finally{
        $requestStream.Close()
        $requestStream.Dispose()
    }
}

#Function to get a list of files in an FTP directory
Function Get-FTPFileList { 
    Param (
     [System.Uri]$server,
     [string]$username,
     [string]$password,
     [string]$directory
    )

    $uri =  "$server$directory"

    try 
     {
        $FTPRequest = [System.Net.FtpWebRequest]::Create($uri)
        $FTPRequest.Credentials = New-Object System.Net.NetworkCredential($username, $password)
        $FTPRequest.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $FTPResponse = $FTPRequest.GetResponse() 

        $responseStream = $FTPResponse.GetResponseStream()
        $streamReader = New-Object System.IO.StreamReader $ResponseStream  
        
        $files = New-Object System.Collections.ArrayList
        While ($file = $StreamReader.ReadLine())
         {
           [void] $files.add("$file")
      
        }
    }
    finally{
        $streamReader.close()
        $responseStream.close()
        $FTPResponse.Close()
    }

    Return $files
}

#Get the oldest 10 files in the local directory
$fileBatch = Get-ChildItem $localDirectory | Where-Object { -not $_.PsIsContainer } | Sort-Object LastWriteTime | Select-Object -first $batchSize

while ($fileBatch.Count -gt 0) {
    
    #Check if there are already too many files in the FTP directory
    while ((Get-FTPFileList -server $server -username $username -password $password -directory $remoteDirectory).Count -gt $maxFTPFiles){
        Write-Host "Waiting for FTP directory to empty"
        Start-Sleep -Seconds $FTPPollRate
    }
    
    #Upload and move the files
    foreach ($file in $fileBatch){
        try{
            Upload-FTPFile -server $server -username $username -password $password -directory $remoteDirectory -file $file
            Move-Item $file.FullName "$localDirectory/done/"
            Write-Host "Uploaded $file"
        }
        catch{
            write-host -message $_.Exception.InnerException.Message
        }
    }

    #Load the next batch of files
    $fileBatch = Get-ChildItem $localDirectory | Where-Object { -not $_.PsIsContainer } | Sort-Object LastWriteTime | Select-Object -first 10

}

 
