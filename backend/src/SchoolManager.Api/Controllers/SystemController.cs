using Microsoft.AspNetCore.Mvc;
using SchoolManager.Api.Multitenancy;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/system")]
public sealed class SystemController(ITenantContext tenantContext) : ControllerBase
{
    [HttpGet("ping")]
    public IActionResult Ping()
    {
        return Ok(new
        {
            status = "ok",
            tenant = tenantContext.TenantId ?? "not-provided"
        });
    }
}
