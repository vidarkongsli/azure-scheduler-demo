## The bird’s-eye view
Scheduler is a quite simple component in the quite vast set of services and functionalities offered by Windows Azure. It should not be confused with the WebJobs feature in Windows Azure Web Sites, which enables running programs or scripts in your web site at certain times (either on-demand or on a schedule). Scheduler lets you perform two types of actions (or three, depending on how you look at it):

1. Accessing an HTTP or HTTPS endpoint, using a preselected method (aka “HTTP verb”) and possibly delivering a given payload, or
2. Sending a message to a Windows Azure Storage Queue with a given payload.

From an architecture view the core functionality that Scheduler offers, is removing the scheduling logic out from your application, to a configurable component. In this respect, is could be seen as an alternative to frameworks such as [Quarz.NET](http://www.quartz-scheduler.net/), Scheduled Tasks in Windows, and cron on UNIX systems. I would argue that the Azure Scheduler is very similar to [Scheduled Tasks](https://developers.google.com/appengine/docs/python/config/cron) that has been available in Google AppEngine for several years. Also note that the Scheduler does not care about the application logic at all, on which platform it is implemented, or where it runs. As long as it is available using HTTP from Windows Azure or reads from a Windows Azure Storage Queue, it will work.
## Fundamentals
When you get introduced to Scheduler, you will experience a few terms being thrown around that might be a little confusing. I was a bit confused, anyway. The first term is “cloud service”, which, according to the [documentation](http://msdn.microsoft.com/en-us/library/windowsazure/dn528941.aspx) "represents an application". When you create a new scheduled job, you do not need to know about this term as it is automatically assigned based on the location you select. For example, when selecting “North Europe” as location I got assigned the cloud service name of *CS-NorthEurope-scheduler*.

The most fundamental term in Scheduler is "job". A job represents an action to be performed at a certain time, and your jobs can be grouped into job collections. There is no functional reason for grouping jobs into collections; they can cross application and functional boundaries helter-skelter. However, all jobs in a collection are grouped in a certain data center location, and quota enforcements are made based on collections.

Recurrence is about when the job is to be run. Either the job is set to occur at a specific time in the future, on a specific interval, or on a (more or less) advanced schedule. As the time of writing, the possibility of creating an advanced schedule is not available in the management console, and the REST interface offering more advanced options seem a little buggy. I will get back to this in part three of this series. 
## Choosing an action type
As I mentioned earlier, there are two main types of actions: HTTP/S and Storage Queue. If we get into details, we actually have to consider HTTP and HTTPS as two different types but I would argue that HTTP in general could have security ramifications that you should think deeply about. I would thus in most circumstances advice you to use HTTPS instead of HTTP. 

So, what action type should you use? Here is some guidance:

|**Action type**|**HTTP**|
| -------------------- | ----------- |
|Basics|Visits an HTTP URL using a given method with a predefined, static payload|
|Pros|This is by far the simplest action type with respect to configuration.|
|Cons|Not good for triggering long-running jobs, as you might experience timeouts at the HTTP level or in the web application. Furthermore, the URL would have to be secured which could be difficult in a cloud scenario|
|Use for|Triggering brief jobs that completes quickly|

|**Action type**|**HTTPS**|
| -------------------- | ----------- |
|Basics	|Visits an HTTPS URL using a given method with a predefined, static payload|
|Pros	|Using HTTPS adds confidentiality and integrity to the payload sent in the request|
|Cons	|Could be a wee bit harder to configure your app to use HTTPS. However, if your application uses Azure WebSites, HTTPS is available out of the box.|
|Use for|Triggering brief jobs that completes quickly|

|**Action type**|**Storage queue**|
| -------------------- | ----------- |
|Basics	|Places a message into a Windows Azure Storage Queue, with a given, static payload|
|Pros	|Offers setting up authentication of the Scheduler to the Queue. Queue is access-controlled out of the box. Allows for asynchronous processing of jobs.|
|Cons	|Would need a component that reads messages from the queue, and executes them. For instance, a WorkerRole, requires a somewhat more complex setup and deployment than compared to Azure Web Sites.|
|Use for	|Long-running jobs that can be executed asynchronically|
## Setting up a storage queue job
So, having gone thru some of the fundamentals and some considerations on which action type to use, let us try to set up a storage queue job. In this setup, I will show how to create an Azure WorkerRole that handles the messages that the Scheduler enters into the queue.

As the time of writing, the Scheduler is in preview, so the first thing you need to do is to sign up for the preview [here](https://account.windowsazure.com/PreviewFeatures?fid=scheduler).
When you have access to the preview, you should have an entry in the menu on the left of the Windows Azure Management Console.

![Scheduler item in Management Console](https://bekkopen.blob.core.windows.net/attachments/57623656-4eef-418a-8b11-3f9dbf504306)

Click on the *Scheduler* item, and select *New-->App Services-->Scheduler-->Custom Create*, which will bring up the following dialog:

![Selecting job collection for new job] (https://bekkopen.blob.core.windows.net/attachments/13288af6-5e08-42df-9d33-02d7e0f3e1f9)

Here I have selected to create a new job collection in the North Europe datacenter. Clicking the right arrow icon in the lower right corner brings me to the next dialog:

![Defining job action] (https://bekkopen.blob.core.windows.net/attachments/02c7e539-130c-48df-9440-bcd1b0202d95)

I have selected an action type of storage queue, and selected a queue in an existing storage account. You could also choose to create a new storage account and queue at this point. I have also clicked on the *Generate SAS token* which creates a token that the Scheduler needs to be able to access the queue. I have also selected to include a payload in the body of the message, which signals to the receiving application what it is supposed to do. In terms of the architecture of my solution I could also have chosen to have a separate queue for each action my solution is to take. Then I would not need to have anything in the message body. An empty message would suffice to trigger the given functionality.

Finally, I need to define the schedule for the job:

![Defining recurrence] (https://bekkopen.blob.core.windows.net/attachments/a2793ddf-a84d-4461-b6c7-df63c4b116b6)

I have chosen to make this job a recurring job, scheduled to run every night at 1 am for the next year.

Note that once created, there is no way to alter the job in the management console. You have to use the REST interface for that. I suspect this will be better when the Scheduler is released.

We now have set up the Scheduler to create queue entries, but we have no application to process them. Before creating the application, you can use any Azure Storage Explorer utility to peek into the queue to see if the entries appear. 
## Setting up a message processor
As I mentioned earlier, the storage queue job type requires some component in your system to process the messages. Here, I will create a basic Azure WorkerRole application that does this. I am using Visual Studio 2013 for this, targeting .NET 4.5.
In Visual Studio, I will select *File-->New Project*, and use the Windows Azure Cloud Service project template:

![Creating a cloud project in Visual Studio] (https://bekkopen.blob.core.windows.net/attachments/9b95f38f-691d-4e3a-b516-eeb0ad91c8c4)

I then get prompted to enter the roles needed in my Cloud Service, and I create a Worker Role which I name “EmailWorkerRole”:

![Adding roles a cloud project] (https://bekkopen.blob.core.windows.net/attachments/9f2dae78-157c-471e-8f55-c19ef78021a5)

The first thing I will set up, is the connection string for the application to use for connecting to the storage queue. The first step is to define a setting for this in the <code>ServiceDefinition.csdef</code> file:
```XML 
<?xml version="1.0" encoding="utf-8"?>
<ServiceDefinition name="azurescheduler_demo" xmlns="http://schemas.microsoft.com/ServiceHosting/2008/10/ServiceDefinition" schemaVersion="2013-10.2.2">
  <WorkerRole name="EmailWorkerRole" vmsize="ExtraSmall">
    <Imports>
      <Import moduleName="Diagnostics" />
    </Imports>
    <ConfigurationSettings>
      <Setting name="StorageConnectionString" />
    </ConfigurationSettings>
  </WorkerRole>
</ServiceDefinition>
```
The next step is to define the connection string itself. For production use, this is done in the <code>ServiceConfiguration.Cloud.cscfg</code> file. A connection string for Azure Storage takes the form of

> DefaultEndpointsProtocol=http;AccountName=myAccount;AccountKey=myKey;

The AccountName is simply the name of your account. In the example from above, this is *sojourn*. The account key can be found in the Azure Management Console by navigating to the given storage account and selecting *Manage access key* at the bottom of the page:

![Finding access keys for a storage service] (https://bekkopen.blob.core.windows.net/attachments/0b9c6024-833f-444c-9f41-6eb9d5ed0fa9)

In the dialog box that pops up click the "copy to clipboard" icon of either the primary or the secondary key. It does not matter which one you choose:

![Copying a storage access key to the clipboard] (https://bekkopen.blob.core.windows.net/attachments/6c2f4d5d-7985-4a16-897a-bb9aa3a9fffc)

Then use this key as the <code>AccountKey</code> in the connection string, making the connection string something like this:

> DefaultEndpointsProtocol=https;AccountName=sojourn;AccountKey=VQ9gsCB...;

(I recommend you use HTTPS for <code>DefaultEndpointsProtocol</code>, not HTTP)

Enter the value of this connection string into the <code>ServiceConfiguration.Cloud.cscfg</code>code> file, defining the <code>StorageConnectionString</code> setting:
```XML
<?xml version="1.0" encoding="utf-8"?>
<ServiceConfiguration serviceName="azurescheduler_demo" xmlns="http://schemas.microsoft.com/ServiceHosting/2008/10/ServiceConfiguration" osFamily="3" osVersion="*" schemaVersion="2013-10.2.2">
  <Role name="EmailWorkerRole">
    <Instances count="1" />
    <ConfigurationSettings>
      <Setting name="Microsoft.WindowsAzure.Plugins.Diagnostics.ConnectionString" value="UseDevelopmentStorage=true" />
      <Setting name="StorageConnectionString" value="DefaultEndpointsProtocol=https;AccountName=sojourn;AccountKey=VQ9gsCB..."/>
    </ConfigurationSettings>
  </Role>
</ServiceConfiguration>
```
Also, notice the <code>Microsoft.WindowsAzure.Plugins.Diagnostics.ConnectionString</code> setting already present in the <code>ServiceConfiguration.Cloud.cscfg</code>. This denotes the storage account that the built-in diagnostics will log to, and this is very useful for debugging purposes. Change the value of this setting to the same connection string as for the <code>StorageConnectionString</code>. This will enable you to easily read the results of our test execution later on.

The configuration now is in place. The next step is to write some code. The Cloud template in Visual Studio has provided a basic scaffold code for us. The first thing to do is to create a class <code>EmailProcessor</code> that will be called from the <code>WorkerRole</code> class. Enter two lines into the original code: one to create a new object instance, and one to call the <code>ProcessMessagesFromQueue</code> method:
```C#
public class WorkerRole : RoleEntryPoint
{
    public override void Run()
    {
        // This is a sample worker implementation. Replace with your logic.
        Trace.TraceInformation("EmailWorkerRole entry point called");
        var emailProcessor = new EmailProcessor();

        while (true)
        {
            Thread.Sleep(10000);
            Trace.TraceInformation("Working");
            emailProcessor.ProcessMessagesFromQueue();
        }
    }
}
```
Here is the <code>EmailProcessor</code> class:
```C#
public class EmailProcessor
{
    private readonly CloudQueue _queue;
    public EmailProcessor()
    {
        var storageAccount = CloudStorageAccount.Parse(CloudConfigurationManager.GetSetting("StorageConnectionString"));
        var queueClient = storageAccount.CreateCloudQueueClient();
        _queue = queueClient.GetQueueReference("email");
    }

    public void ProcessMessagesFromQueue()
    {
        _queue.CreateIfNotExists();
        foreach (var cloudQueueMessage in _queue.GetMessages(10, TimeSpan.FromMinutes(5)))
        {
            var messageContent = cloudQueueMessage.AsString;
            Trace.TraceInformation("Processing request: {0}", messageContent);
            _queue.DeleteMessage(cloudQueueMessage);
        }
    }
}
```
In the constructor, the connection string for the storage account is read, and the queue *email* is initialized. In the <code>ProcessMessagesFromQueue</code> method, the queue is created if it does not exist. Then we query the queue for the first 10 messages, and sets the queue to make the messages invisible on the queue for five minutes. If we are not done with processing the messages in five minutes, they will be available for others to process. In the for-loop, we handle each message by simply writing a log message before we delete it.

In order for diagnostics to send our log entries to the storage, we have to add these lines to the <code>OnStart</code> method in the <code>WorkerRole</code> class:
```C#
var diagConfig = DiagnosticMonitor.GetDefaultInitialConfiguration();
            
diagConfig.Logs.ScheduledTransferLogLevelFilter = LogLevel.Information;
diagConfig.Logs.ScheduledTransferPeriod = TimeSpan.FromMinutes(5);
DiagnosticMonitor.Start("Microsoft.WindowsAzure.Plugins.Diagnostics.ConnectionString", diagConfig);
```
Note that we here set the logs to be transferred to storage once every five minutes, which means that we can experience up to five minutes delay before our log messages are available. For more efficient debugging, you might consider setting this to a lower value.
We can now build our project, and we are ready for deployment.

On the context menu of the solution in solution explorer, click on the *Publish* item:

![Publishing a cloud application from Visual Studio] (https://bekkopen.blob.core.windows.net/attachments/660884b1-03ad-48d9-9ade-db58a9cb6ced)

Since we have no could service to deploy to, we choose to create a new one:

![Creating a cloud service to deploy to from Visual Studio] (https://bekkopen.blob.core.windows.net/attachments/0ff912d6-2c8e-43d1-8378-7a8a951bf11e)

We use the default settings for the rest, and press *Publish*:

![Publish settings summary] (https://bekkopen.blob.core.windows.net/attachments/33106d88-1583-488f-b9d1-1b3a12ed3b05)

Publishing normally takes a few minutes, more often than not less than ten minutes. Once the application is up and running we can use a storage explorer to investigate our logs (I use [Azure Storage Explorer](http://azurestorageexplorer.codeplex.com/)). Here, we can see that our application has processed the message:

![Viewing diagnostics log entries in Azure Storage] (https://bekkopen.blob.core.windows.net/attachments/395e1607-0699-4432-bd59-2c69d4b9c68b)

## In closing
I have explained the basic concepts of the Windows Azure Scheduler, and discussed what you can use it for, and what types of actions you can set up. Then, I went on to show an example on how to create a storage queue action and made a simple application to respond to these actions. Storage queue actions are especially good for processing tasks that might take a long time to complete asynchronically. Note that in our example, when popping messages off the queue, we made them invisible for five minutes. This means that we have five minutes to complete the processing. If your task might take longer, you should extend this timespan.

As I mentioned before, using storage queue actions requires some extra configuration which adds some complexity. If you already have a web application set up in your system, and your tasks typically execute quickly, you should probably use an HTTP/S action type instead, which will investigate in a later post.

You can find the sample code in this post on GitHub.

Suggestions and comments are very welcome. 