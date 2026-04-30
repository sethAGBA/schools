using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Data;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/platform/audit")]
[Authorize(Policy = "SuperAdminOnly")]
public sealed class PlatformAuditController(SchoolDbContext dbContext) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(
        [FromQuery] string? targetTenantId,
        [FromQuery] int take = 100,
        CancellationToken cancellationToken = default)
    {
        var boundedTake = Math.Clamp(take, 1, 500);
        var query = dbContext.AuditLogs.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(targetTenantId))
        {
            var tenantId = targetTenantId.Trim().ToLowerInvariant();
            query = query.Where(x => x.TargetTenantId == tenantId);
        }

        var logs = await query
            .OrderByDescending(x => x.CreatedAtUtc)
            .Take(boundedTake)
            .Select(x => new
            {
                x.Id,
                x.ActorUserId,
                x.ActorEmail,
                x.ActorRole,
                x.Action,
                x.TargetType,
                x.TargetId,
                x.TargetTenantId,
                x.MetadataJson,
                x.CreatedAtUtc
            })
            .ToListAsync(cancellationToken);

        return Ok(logs);
    }
}
