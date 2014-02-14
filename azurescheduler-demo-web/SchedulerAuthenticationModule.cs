using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Claims;
using System.Threading;
using System.Web;
using System.Configuration;

namespace azurescheduler_demo_web
{
    public class SchedulerAuthenticationModule : IHttpModule
    {
        private string _sharedSecret;
        public void Init(HttpApplication context)
        {
            _sharedSecret = GetSharedSecretFromConfig();
            context.AuthenticateRequest += AuthenticateScheduler;
        }

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

        void AuthenticateScheduler(object sender, EventArgs e)
        {
            var application = (HttpApplication) sender;
            var request = new HttpRequestWrapper(application.Request);
            if (!request.Headers.AllKeys.Contains("x-ms-scheduler-jobid")) return;

            AuthenticateUsingSharedSecret(request);
        }

        private void AuthenticateUsingSharedSecret(HttpRequestBase request)
        {
            Trace.TraceInformation("Trying to read shared secret from request body");
            using (var sr = new StreamReader(request.GetBufferedInputStream(), request.ContentEncoding))
            {
                var bodyContent = sr.ReadToEnd();
                if (!bodyContent.StartsWith("secret:")) return;
                var secret = bodyContent.Replace("secret:", string.Empty).Trim();
                if (secret != _sharedSecret) return;
            }
            CreateClaimsForScheduler();
        }

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

        public void Dispose()
        {
        }
    }
}