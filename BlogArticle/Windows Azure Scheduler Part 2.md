## Creating the application using ASP.NET Web API
Before we set up our Scheduler job, let’s make a sample application that we will trigger from our action. I will base this on ASP.NET 4.5 using Web API and I will add a new web project to the Visual Studio solution that I used in my previous post by selecting *Add-->New project...* on the solution context menu in solution explorer.

I then select the ASP.NET MVC 4 Web Application template and name the project *azurescheduler-demo-web*:

![Add new project - ASP.NET MVC 4 Web Application](https://bekkopen.blob.core.windows.net/attachments/0d5682e4-a006-4aec-96e7-9145b263197b)

On the next dialog box, I select to make a Web API project:

![New ASP.NET MVC 4 Project dialog - select Web API template](https://bekkopen.blob.core.windows.net/attachments/62079bd5-efc6-4bfc-82f3-d423323d95eb)

Once the project has been set up, and I have verified that it builds, I add a new Web API Controller by selecting *Add-->New item...* on the web project and I name it ScheduleController:

![Add controller - ScheduleController] (https://bekkopen.blob.core.windows.net/attachments/ab93e99b-c66b-47ae-b456-c869483e19e9)

I make the class very simple:
```csharp
public class ScheduleController : ApiController
{
    [HttpPost]
    public HttpResponseMessage UpdateNews()
    {
        Trace.TraceInformation("Processing UpdateNews request");
        return Request.CreateResponse(HttpStatusCode.Accepted);
    }
}
```
I have created a simple method that only creates some log information, and returns a 202 Accepted HTTP message. Because calling this API method in a real scenario would have a permanent side effect, I choose to make it available for POST requests only to adhere to the HTTP method semantics.
In order for trace information to be available for the Azure Web Site, I need to add the following to the <code>&lt;configuration&gt;</code> element in the <code>Web.Config</code>:
```xml
<system.diagnostics>
    <trace>
      <listeners>
        <add name="WebPageTraceListener"
            type="System.Web.WebPageTraceListener, 
            System.Web, 
            Version=4.0.0.0, 
            Culture=neutral,
            PublicKeyToken=b03f5f7f11d50a3a" />
      </listeners>
    </trace>
  </system.diagnostics>
```
The application is then ready for publishing to an Azure Web Site, so I select *Publish...* on the context menu for the web project. I have no web site set up and no corresponding publishing profile, so then click on the *Import*-button, and then select to *Import from a Windows Azure Web Site*, and select *New...*:

![Import publish settings dialog](https://bekkopen.blob.core.windows.net/attachments/5b03a682-07cf-4134-b697-a50883bf999a)

Then, name the site and press *Create*:

![Create site on Windows Azure dialog](https://bekkopen.blob.core.windows.net/attachments/aefed354-a2db-497c-8015-af83724ca537)

The web site will be created, and the profile is ready:

![Publish web dialog](https://bekkopen.blob.core.windows.net/attachments/5792a19d-b96f-4043-b598-4b3584178952)

Then, press *Publish*, and the application will be published. Our application is now ready to be triggered by the Scheduler.
## Configuring the HTTPS job
In my last post, I argued that HTTP and HTTPS action types in Scheduler jobs are quite similar. I will thus only show an HTTPS example, as I would strongly suggest that you use this variant. Now that our application is ready, and has a URL to visit (https://azurescheduler-demo-web.azurewebsites.net/api/schedule/updatenews), we can set up a Scheduler job. Name this job, make it an HTTPS action type, use POST as method, and point it to the URL of the application, similar to the one given above. Here's an example:

![Create job action - update_news](https://bekkopen.blob.core.windows.net/attachments/63992081-398a-4a28-a365-74d02f1018ee)

Before moving on, it would be OK to check that our setup works so far. We have already instrumented our application using .NET Diagnostics, so let's have a look at the logs. First, enable application logging in the Azure Web Site. This is done using the Server Explorer in Visual Studio, by bringing up the context menu on the Web Site and selecting *Properties*. Then, set the application logging entry to *Information*:

![Setting 'Application logging' to 'Information'](https://bekkopen.blob.core.windows.net/attachments/84fe7867-682a-4b61-be04-0a71111a3042)

Save the changes, go back to the context menu for the Web Site and select *View Streaming Logs in Output Window*:

![Switching on 'View Streaming Logs in Output Window'](https://bekkopen.blob.core.windows.net/attachments/7a0fc8ab-7f57-48a5-83e5-b2d8db3557f1)

Then, observe the application log stream in the Visual Studio output window:

![View streaming application log in Visual Studio](https://bekkopen.blob.core.windows.net/attachments/4171b09e-1deb-4963-b8f1-824b537a5313)

(You might want to switch off the live log streaming once you are done - go back to the Web Site context menu to do that)

## Security – oh my!
But hang on. We have now exposed a URL in our application that is open for everyone to visit. This is not good. In normal circumstances, we want only the Scheduler to visit this URL to trigger the tasks performed by the application. In the Storage Queue Action type, we use an access token to gain access to the queue, but the HTTP/S action type does not have any form of authentication built in. 

The Scheduler adds a number of custom HTTP headers to the request named *x-ms-scheduler-**.

We can certainly use the presence of one of these headers to identify the Scheduler, but headers can be easily added to a request, so we need some sort of authentication. For simplicity, we shall here rely on a shared secret that we will add to the message body of the request from the Scheduler.

So, we will authenticate the Scheduler in the application based on:

1. The presence of the HTTP header *x-ms-scheduler-jobid* in the request, and
2. the  predefined shared secret inside the body of the request

In this example, we are based on ASP.NET 4.5, and the revamped security stack new in this version of the framework. In detail, we will rely on role based access control inside our Web API controller, and we will create a custom authentication module that authenticates the caller and issuing role claims for it for the rest of the application to use.

First, let’s set up access control in our API. We do this by defining a role *scheduler* and adds an <code>AuthorizeAttribute</code> to the controller:
```csharp
[Authorize(Roles = "scheduler")]
public class ScheduleController : ApiController
{
    [HttpPost]
    public HttpResponseMessage UpdateNews()
    {
        Trace.TraceInformation("Processing UpdateNews request");
        return Request.CreateResponse(HttpStatusCode.Accepted);
    }
}
```
Now, that was simple. Next step is a bit more intricate. Let’s create an <code>IHttpModule</code> implementation that performs authentication in the ASP.NET [application pipeline](http://msdn.microsoft.com/en-us/library/bb470252.aspx). Let’s create a class <code>SchedulerAuthenticationModule</code>, and use this scaffold: 
```csharp
public class SchedulerAuthenticationModule : IHttpModule
{
    public void Init(HttpApplication context)
    {
       context.AuthenticateRequest += AuthenticateScheduler;
    }
    void AuthenticateScheduler(object sender, EventArgs e)
    {
        var application = (HttpApplication) sender;
        var request = new HttpRequestWrapper(application.Request);    
    }

    public void Dispose()
    {
    }
}
```
Then the first we will add is some code to check for the presence of the custom HTTP headers that the Scheduler is known to include. If they are not there, the module will just quit and give control back to the pipeline:
```csharp
void AuthenticateScheduler(object sender, EventArgs e)
{
    var application = (HttpApplication) sender;
    var request = new HttpRequestWrapper(application.Request);
    if (!request.Headers.AllKeys.Contains("x-ms-scheduler-jobid")) return;

    AuthenticateUsingSharedSecret(request);
}
```
If the header is present, we call the <code>AuthenticateUsingSharedSecret</code> method, which extracts the body of the request. If the body content is prefixed with *secret:*, we will extract what is after this in the message, and compare that to our known secret:
```csharp
private void AuthenticateUsingSharedSecret(HttpRequestBase request)
{
    Trace.TraceInformation("Trying to read shared secret from request body");
    using (var sr = new StreamReader(request.GetBufferedInputStream(), request.ContentEncoding))
    {
        var bodyContent = sr.ReadToEnd();
        if (!bodyContent.StartsWith("secret:")) return;
        var secret = bodyContent.Replace("secret:", string.Empty).Trim();
        if (secret != GetSharedSecretFromConfig()) return;
    }
    CreateClaimsForScheduler();
}
```
If we don’t find any secret in the body, or if the secret in the request body is not equal to our known secret, we will return. If the secret in the request matches our secret, we will call <code>CreateClaimsForScheduler()</code> to create claims for the scheduler. This method looks like this:
```csharp
private static void CreateClaimsForScheduler()
{
    var nameIdClaim = new Claim(ClaimTypes.NameIdentifier, "scheduler");
    var schedulerRoleClaim = new Claim(ClaimTypes.Role, "scheduler");
    var identificatorClaim =
        new Claim(
            "http://schemas.microsoft.com/accesscontrolservice/2010/07/claims/identityprovider",
            "application");

    var claimIdentity = new ClaimsIdentity(new List<Claim>
        {
            nameIdClaim,
            schedulerRoleClaim,
            identificatorClaim
        }, "custom");

    var principal = new ClaimsPrincipal(claimIdentity);

    Thread.CurrentPrincipal = principal;
    HttpContext.Current.User = Thread.CurrentPrincipal;
    Trace.TraceInformation("Identified scheduler. Created claims");
}
```
The most important claim that we add here, is the claim of role *scheduler*. The presence of this role will be used by the access control further down in the request processing to grant access to our method in the controller that we set up previously. Note also that the principal that we created is assigned both as the <code>Thread.CurrentPrincipal</code> and <code>HttpContext.Current.User</code>. This makes the application able to fetch the principal using all available methods from the .NET framework, and makes the authentication method loosely coupled with the rest of the application.
One piece of the puzzle is still missing: where does the application store the shared secret, and how does retrieve it? We will add the secret to <code>appSettings</code> in <code>Web.Config</code> and use the <code>GetSharedSecretFromConfig</code> method to retrieve it:
```csharp
private static string GetSharedSecretFromConfig()
{
    const string appSettingsKey = "scheduler.secret";
    if (ConfigurationManager.AppSettings.AllKeys.Contains(appSettingsKey))
    {
        return ConfigurationManager.AppSettings[appSettingsKey];
    }
    Trace.TraceWarning("Could not find '{0}' in AppSettings.", appSettingsKey);
    return default(string);
}
```
Add the secret to <code>Web.Config</code>:
```xml
<appSettings>
    <add key="scheduler.secret" value="44139710149444462369" />
</appSettings>
```
Finally, we have to register the <code>SchedulerAuthenticationModule</code> as an HTTP module in <code>Web.Config</code> by adding the following to the <code>system.webServer</code> element:
```xml
<modules>
    <add name="SchedulerAuthenticationModule" type="azurescheduler_demo_web.SchedulerAuthenticationModule, azurescheduler-demo-web" preCondition="managedHandler" />
</modules>
```
Publish the application again, and we are ready to go.

The next time the Scheduler executes the job, we will see that it will get a not allowed response from the server. This can be seen in the job history in the Azure Management Console. What are we missing? It’s the shared secret in the request body.

Unfortunately, as the time of writing there is no possibility to change an existing job using the Management Console, so we need to delete our old job and create a new one. (More on that on a later post). So, in the new job, include the secret:

![Creating job action with shared secret in body](https://bekkopen.blob.core.windows.net/attachments/54961fa0-bb97-473e-a9bb-68693a41dfd5)

## Summary
This concludes the second post in the series in Azure Scheduler. We have seen how we can use the HTTP/S action type to call into an ASP.NET Web API controller, and how to secure the access to the URL. Since we are sending a shared secret over the wire, it is recommended that you use HTTPS exclusively, which will protect the secret.

You can find the sample code in this post on [GitHub](https://github.com/vidarkongsli/azure-scheduler-demo/).

Suggestions and comments are very welcome.