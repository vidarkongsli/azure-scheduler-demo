using System;
using System.Diagnostics;
using System.Net;
using System.Threading;
using Microsoft.WindowsAzure.Diagnostics;
using Microsoft.WindowsAzure.ServiceRuntime;
using LogLevel = Microsoft.WindowsAzure.Diagnostics.LogLevel;

namespace EmailWorkerRole
{
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

        public override bool OnStart()
        {
            // Set the maximum number of concurrent connections 
            ServicePointManager.DefaultConnectionLimit = 12;

            // For information on handling configuration changes
            // see the MSDN topic at http://go.microsoft.com/fwlink/?LinkId=166357.

            var diagConfig = DiagnosticMonitor.GetDefaultInitialConfiguration();
            
            diagConfig.Logs.ScheduledTransferLogLevelFilter = LogLevel.Information;
            diagConfig.Logs.ScheduledTransferPeriod = TimeSpan.FromMinutes(5);
            DiagnosticMonitor.Start("Microsoft.WindowsAzure.Plugins.Diagnostics.ConnectionString", diagConfig);
                    
            return base.OnStart();
        }
    }
}
