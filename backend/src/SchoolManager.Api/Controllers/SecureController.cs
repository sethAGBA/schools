using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/secure")]
[Authorize]
public sealed class SecureController : ControllerBase
{
    [HttpGet("me")]
    public IActionResult Me()
    {
        return Ok(new
        {
            email = User.FindFirst("email")?.Value,
            tenantId = User.FindFirst("tenant_id")?.Value,
            role = User.FindFirst("http://schemas.microsoft.com/ws/2008/06/identity/claims/role")?.Value
        });
    }

    [HttpGet("admin")]
    [Authorize(Policy = "AdminOnly")]
    public IActionResult AdminOnly() => Ok(new { allowed = true, policy = "AdminOnly" });

    [HttpGet("super-admin")]
    [Authorize(Policy = "SuperAdminOnly")]
    public IActionResult SuperAdminOnly() => Ok(new { allowed = true, policy = "SuperAdminOnly" });

    [HttpGet("staff")]
    [Authorize(Policy = "StaffOrAdmin")]
    public IActionResult StaffOrAdmin() => Ok(new { allowed = true, policy = "StaffOrAdmin" });
}
