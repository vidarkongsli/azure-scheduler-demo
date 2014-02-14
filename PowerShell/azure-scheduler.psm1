<#
Copyright 2014 Vidar Kongsli

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0
  
Unless required by applicable law or agreed to in writing, software 
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
#>
function get-azuremanagementhttpclient($xMsVersionHeader='2013-08-01') {
  $cert = Get-AzureSubscription -Current | select -ExpandProperty Certificate                
  add-type -AssemblyName System.Net.Http                                                             
  add-type -AssemblyName System.Net.Http.WebRequest                                                   
  $handler = New-Object System.Net.Http.WebRequestHandler                                             
  $handler.ClientCertificates.Add($cert) | out-null                                                              
  $httpClient = new-object System.Net.Http.HttpClient($handler)                                       
  $httpClient.DefaultRequestHeaders.Add('x-ms-version', $xMsVersionHeader)                                 
  $mediaType = new-object System.Net.Http.Headers.MediaTypeWithQualityHeaderValue('application/xml')  
  $httpClient.DefaultRequestHeaders.Accept.Add($mediaType)                                            
  $httpClient
}

function update-azuremanagementrequest {
  [CmdLetBinding()]
  PARAM(
    [Parameter(Mandatory=$true)]
    $path, 
    [Parameter(Mandatory=$true)]
    $content, 
    [Parameter(Mandatory=$true)]
    $returnRawString,
    [Parameter(Mandatory=$false)]
    $apiVersion='2013-10-31_Preview'
    )
  $subId = Get-AzureSubscription -Current | select -ExpandProperty SubscriptionId
  Write-Debug "Using subscription $($subId)"
  $client = get-azuremanagementhttpclient
  $method = New-Object System.Net.Http.HttpMethod('PATCH')
  $uri = "https://management.core.windows.net/$subId/$($path)?api-version=$apiVersion"
  Write-Debug "$method on $uri" 
  $request = New-Object System.Net.Http.HttpRequestMessage($method, $uri)
  $request.Content = New-Object System.Net.Http.StringContent($content, [System.Text.Encoding]::UTF8, 'application/json')
  $task = $client.SendAsync($request)
  _waitAndHandleResult $task $returnRawString   
}

function _waitAndHandleResult($task, $returnRawString) {
  $task.Wait()                                                                            
  if($task.Result.IsSuccessStatusCode -eq "True")
  {
    $mediaType = $task.Result.Content.Headers.ContentType.MediaType
    Write-Debug "Response Content-type: $mediaType"
    $res = $task.Result.Content.ReadAsStringAsync().Result
    if (-not($returnRawString) -and $mediaType -eq 'application/xml') {
      [xml]$res
    } elseif (-not($returnRawString) -and ($mediaType -eq 'application/json')) {
      ConvertFrom-Json -InputObject $res
    } else {
      $res
    }
  } 
  else
  {
    $errorInfo = $task.Result.Content.ReadAsStringAsync().Result
    $errorStatus = $task.Result.StatusCode
    Write-Error "Call to GET $uri failed with HTTP code $errorStatus and message $errorInfo"
    $null
  }
}

function get-azuremanagementrequest {
  [CmdLetBinding()]
  PARAM(
    [Parameter(Mandatory=$true)]
    $path, 
    [Parameter(Mandatory=$true)]
    $returnRawString,
    [Parameter(Mandatory=$false)]
    $apiVersion='2013-10-31_Preview'
    )
  $subId = Get-AzureSubscription -Current | select -ExpandProperty SubscriptionId
  Write-Debug "Using subscription $($subId)"
  $client = get-azuremanagementhttpclient
  $uri = "https://management.core.windows.net/$subId/$($path)?api-version=$apiVersion"
  Write-Debug "GET on $uri"
  $task = $client.GetAsync($uri)                                          
  _waitAndHandleResult $task $returnRawString 
}

$_collection_url = 'cloudservices/$($schedulerServiceName)/resources/scheduler/~/JobCollections/$collectionName'
$_jobs_url       = $_collection_url + '/jobs'
$_job_url        = $_collection_url + '/jobs/$jobId'
$_job_history_url= $_collection_url + '/jobs/$jobId/history'

function get-azureschedulerjobcollection
{
  [CmdLetBinding()]
  PARAM(
    [Parameter(Mandatory=$true)]
    $schedulerServiceName, 
    [Parameter(Mandatory=$true)]
    $collectionName,
    [Parameter(Mandatory=$false)]
    $returnRawString=$false
    )
  get-azuremanagementrequest $ExecutionContext.InvokeCommand.ExpandString($_collection_url) -returnRawString $returnRawString
}

function get-azureschedulerjobs
{
  [CmdLetBinding()]
  PARAM(
    [Parameter(Mandatory=$true)]
    $schedulerServiceName, 
    [Parameter(Mandatory=$true)]
    $collectionName,
    [Parameter(Mandatory=$false)]
    $returnRawString=$false
    )
  get-azuremanagementrequest $ExecutionContext.InvokeCommand.ExpandString($_jobs_url) -returnRawString $returnRawString
}

function get-azureschedulerjob {
  [CmdLetBinding()]
  PARAM(
    [Parameter(Mandatory=$true)]
    $schedulerServiceName, 
    [Parameter(Mandatory=$true)]
    $collectionName,
    [Parameter(Mandatory=$true)]
    $jobId,
    [Parameter(Mandatory=$false)]
    $returnRawString=$false
  )
  get-azuremanagementrequest $ExecutionContext.InvokeCommand.ExpandString($_job_url) -returnRawString $returnRawString
}

function update-azureschedulerjob {
  [CmdLetBinding()]
  PARAM(
    [Parameter(Mandatory=$true)]
    $schedulerServiceName, 
    [Parameter(Mandatory=$true)]
    $collectionName,
    [Parameter(Mandatory=$true)]
    $content,
    [Parameter(Mandatory=$false)]
    $returnRawString=$false
  )  
  
  #Remove properties not allowed in an update request, according to http://msdn.microsoft.com/en-us/library/windowsazure/dn528934.aspx
  if ($content.status) { $content.PSObject.Properties.Remove('status')}
  if ($content.state) { $content.PSObject.Properties.Remove('state')}

  $jobId = $content.id
  Write-Debug "Job ID is $jobId"
  
  if (-not($content -is 'string')) { $content = ConvertTo-Json -InputObject $content -Depth 3 }
  
  update-azuremanagementrequest $ExecutionContext.InvokeCommand.ExpandString($_job_url) $content -returnRawString $returnRawString
}

function get-azureschedulerjobhistory {
  [CmdLetBinding()]
  PARAM(
    [Parameter(Mandatory=$true)]
    $schedulerServiceName, 
    [Parameter(Mandatory=$true)]
    $collectionName,
    [Parameter(Mandatory=$true)]
    $jobId,
    [Parameter(Mandatory=$false)]
    $returnRawString=$false
  )
  get-azuremanagementrequest $ExecutionContext.InvokeCommand.ExpandString($_job_history_url) -returnRawString $returnRawString
}


Export-modulemember -Function `
  update-azuremanagementrequest,get-azuremanagementrequest,get-azureschedulerjobcollection,`
  get-azureschedulerjobs,get-azureschedulerjob,update-azureschedulerjob,get-azureschedulerjobhistory
