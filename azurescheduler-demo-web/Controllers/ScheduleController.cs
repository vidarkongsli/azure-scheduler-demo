using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Web.Http;

namespace azurescheduler_demo_web.Controllers
{
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
}
