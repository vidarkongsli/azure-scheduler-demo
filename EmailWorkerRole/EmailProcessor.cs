using System;
using System.Diagnostics;
using Microsoft.WindowsAzure;
using Microsoft.WindowsAzure.Storage;
using Microsoft.WindowsAzure.Storage.Queue;

namespace EmailWorkerRole
{
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
}