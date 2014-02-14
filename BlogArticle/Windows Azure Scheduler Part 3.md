## Calling the REST API
The most basic thing we need to set up to access the REST API is authentication. The API is requiring you to authenticate using an X-509 v certificate. Luckily, you already have one associated with your Azure Subscription ID, so what you need to do, is to fetch that and use with your request to the API. I assume that you have your Windows Azure PowerShell CmdLets already [set up](http://www.windowsazure.com/en-us/documentation/articles/install-configure-powershell/). Based on the great walk-thru of calling the Azure Management API from PowerShell that I found [here](http://michaelwasham.com/2013/10/08/calling-the-windows-azure-management-api-from-powershell/), I created the following function that returns an HttpClient prepared for calling the Management APIs:
```PowerShell
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
```
It assumes that the Azure PowerShell CmdLets are already loaded into the script context, and that you have a current subscription set up. It fetches the certificate from the subscription, and passes it on to the HttpClient. Furthermore, it adds a custom HTTP header required by the API and it prepares the media type for JSON to the client.

Having the HttpClient prepared, we can make a generic call to the Management API:
```PowerShell
$subId = Get-AzureSubscription -Current | select -ExpandProperty SubscriptionId
$schedulerServiceName = 'CS-NorthEurope-scheduler'
$collectionName = 'demo_jobs'
$client = get-azuremanagementhttpclient
$uri = "https://management.core.windows.net/$subId/cloudservices/$($schedulerServiceName)/resources/scheduler/~/JobCollections/$collectionName/jobs?api-version=$apiVersion"
$task = $client.GetAsync($uri) 
$task.Wait()                                                                            
if($task.Result.IsSuccessStatusCode -eq "True")
{
  $res = $task.Result.Content.ReadAsStringAsync().Result
} else {
  $errorInfo = $task.Result.Content.ReadAsStringAsync().Result
   $errorStatus = $task.Result.StatusCode
   Write-Error "Call to GET $uri failed with HTTP code $errorStatus and message $errorInfo"
}
$res
```
If we run the following output, we yield:
```XML
<Resource xmlns="http://schemas.microsoft.com/windowsazure" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><CloudServiceSettings><GeoRegion>North Europe</GeoRegion></CloudServiceSettings><ETag>9134ee7f-ba2b-4298-b3c1-540c4ee2d0cc</ETag><IntrinsicSettings><Plan>Standard</Plan><Quota><MaxJobCount>50</MaxJobCount><MaxRecurrence><Frequency>Minute</Frequency><Interval>1</Interval></MaxRecurrence></Quota></IntrinsicSettings><Name>demo_jobs</Name><OperationStatus><Error><HttpCode>200</HttpCode><Message>OK</Message></Error><Result>Succeeded</Result></OperationStatus><PromotionCode></PromotionCode><SchemaVersion>1.1</SchemaVersion><State>Started</State><SubState i:nil="true"/><Type>jobcollections</Type></Resource>
```
In the same manner, we can also list all the jobs in the job collection by adding ‘/jobs’ to the end of the request URI, and we get:
```JSON 
[{"id":"send_newsletter","startTime":"2014-02-11T01:00:00Z","action":{"queueMessage":{"storageAccount":"sojourn","queueName":"email","sasToken":"?sv=2012-02-12&si=SchedulerAccessPolicy11.02.2014%2014%3A28%3A22&sig=mSIuQQxWK9t%2BQCn7VGRjKeholH7FNGVLRdp9zriFNtQ%3D","message":"action:send_newsletter"},"type":"storageQueue"},"recurrence":{"frequency":"day","endTime":"2015-02-12T00:00:00Z","interval":1},"state":"enabled","status":{"lastExecutionTime":"2014-02-13T01:00:00.9736795Z","nextExecutionTime":"2014-02-14T01:00:00Z","executionCount":2,"failureCount":0,"faultedCount":0}}]
```
Notice that we now get back JSON instead of XML. Go figure. Anyway, add some code to detect the result format, and parse it accordingly:
```PowerShell
$res = $task.Result.Content.ReadAsStringAsync().Result
$mediaType = $task.Result.Content.Headers.ContentType.MediaType
if ($mediaType -eq 'application/xml') {
      $res = [xml]$res
} elseif ($mediaType -eq 'application/json') {
      $res = ConvertFrom-Json -InputObject $res
}
``` 
Let’s clean our code up a bit and create a reusable function for retrieving a resource:
```PowerShell
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
```
Let’s move on to get information about a job: 
```PowerShell
$job = get-azuremanagementrequest 'cloudservices/CS-NorthEurope-scheduler/res
ources/scheduler/~/JobCollections/demo_jobs/jobs/send_newsletter' -returnRawString $false
$job
```
We see that we get an object graph back which represents the parsed JSON string we got from the server:

![Job object graph returned from the server](https://bekkopen.blob.core.windows.net/attachments/0fb661b1-6437-4476-a06f-aed071679635)

We can also walk the object graph:
```PowerShell
$job.recurrence.frequency # --> ‘day’
```
So, the next step would be to update the job information. For that, we need to send an HTTP request to the server on the resource URI using the PATCH method ([RFC 5789](https://tools.ietf.org/html/rfc5789)). We then create a new function, which is quite similar to the <code>get-azuremanagementrequest</code>:      
```PowerShell
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
```
The most useful scenario for this, is to update the <code>$job</code> object that we got by calling <code>get-azureschedulerequest</code>, and send it back to using our new <code>update-azureschedulerrequest</code> function. But before we do that, we need to remove some items from the object that are [not allowed in an update request](http://msdn.microsoft.com/en-us/library/windowsazure/dn528934.aspx):
```PowerShell
$job.recurrence.interval=2               
$job.PSObject.Properties.Remove('state') #Remove .state 
$job.PSObject.Properties.Remove('status') #Remove .status
$job = ConvertTo-Json -InputObject $job #Create a JSON-formatted string
$updatedJob = update-azuremanagementrequest 'cloudservices/CS-NorthEurope-scheduler/resources/scheduler/~/JobCollections/demo_jobs/jobs/send_newsletter' $job -returnRawString $false
```
We have now completed the cycle of getting job collection information, listing jobs, getting and updating a job.
## Wrapping up
We have now gone through creating PowerShell scripts for accessing the Azure Mangement API, specifically using them for viewing and updating Scheduler information. This have given us some insight into how the API works, and the functions that we have created are generic in the respect that they can be used on other resources in the Management API. I have cleaned up the code, and also made some specific functions for the various Scheduler resources that we can access. You can find this code as a PowerShell module here (!!!!).

Here are some examples of using the cleaned-up functions:
```PowerShell
# Get JobCollection info
$jobCollection = get-azureschedulerjobcollection 'CS-NorthEurope-scheduler' 'demo_jobs'
# List jobs in a collection                                                                                                
$jobs = get-azureschedulerjobs 'CS-NorthEurope-scheduler' 'demo_jobs'
# Get information about the 'send_newsletter' job
$job = get-azureschedulerjob 'CS-NorthEurope-scheduler' 'demo_jobs' 'send_newsletter'
# Change the recurrence interval                                                                                          
$job.recurrence.interval = 1    
# Update the job                                             
$updatedJob = update-azureschedulerjob 'CS-NorthEurope-scheduler' 'demo_jobs'
# Get execution history for a job
$history = get-azureschedulerjobhistory 'CS-NorthEurope-scheduler' 'demo_jobs' 'send_newsletter'        
# Get the latest execution
$history | select -first 1
# Get executions that failed                                                                               
$history | Where-Object { $_.status -eq 'failed' }
```
