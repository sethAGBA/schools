using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Api.Tenants;
using SchoolManager.Modules.Tenancy;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/platform/tenants")]
[Authorize(Policy = "SuperAdminOnly")]
public sealed class PlatformTenantsController(SchoolDbContext dbContext, IAuditLogger auditLogger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken cancellationToken)
    {
        var tenants = await dbContext.Tenants
            .OrderBy(x => x.Name)
            .Select(x => new
            {
                x.Id,
                x.Code,
                x.Name,
                x.IsActive,
                x.CreatedAtUtc
            })
            .ToListAsync(cancellationToken);

        return Ok(tenants);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateTenantRequest request, CancellationToken cancellationToken)
    {
        var code = request.Code.Trim().ToLowerInvariant();
        var name = request.Name.Trim();

        var exists = await dbContext.Tenants.AnyAsync(x => x.Code == code, cancellationToken);
        if (exists)
        {
            return Conflict(new { error = "Un tenant avec ce code existe deja." });
        }

        var tenant = new Tenant
        {
            Code = code,
            Name = name,
            IsActive = true
        };

        dbContext.Tenants.Add(tenant);
        await dbContext.SaveChangesAsync(cancellationToken);
        await auditLogger.LogAsync(
            action: "platform.tenant.created",
            targetType: "Tenant",
            targetId: tenant.Id.ToString(),
            targetTenantId: tenant.Code,
            metadata: new { tenant.Code, tenant.Name },
            cancellationToken);

        return CreatedAtAction(nameof(GetByCode), new { code = tenant.Code }, new
        {
            tenant.Id,
            tenant.Code,
            tenant.Name,
            tenant.IsActive,
            tenant.CreatedAtUtc
        });
    }

    [HttpGet("{code}")]
    public async Task<IActionResult> GetByCode(string code, CancellationToken cancellationToken)
    {
        var normalizedCode = code.Trim().ToLowerInvariant();
        var tenant = await dbContext.Tenants
            .SingleOrDefaultAsync(x => x.Code == normalizedCode, cancellationToken);

        if (tenant is null)
        {
            return NotFound(new { error = "Tenant introuvable." });
        }

        return Ok(new
        {
            tenant.Id,
            tenant.Code,
            tenant.Name,
            tenant.IsActive,
            tenant.CreatedAtUtc
        });
    }

    [HttpPatch("{code}")]
    public async Task<IActionResult> Update(string code, [FromBody] UpdateTenantRequest request, CancellationToken cancellationToken)
    {
        var normalizedCode = code.Trim().ToLowerInvariant();
        var tenant = await dbContext.Tenants.SingleOrDefaultAsync(x => x.Code == normalizedCode, cancellationToken);
        if (tenant is null)
        {
            return NotFound(new { error = "Tenant introuvable." });
        }

        tenant.Name = request.Name.Trim();
        if (request.IsActive.HasValue)
        {
            tenant.IsActive = request.IsActive.Value;
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        await auditLogger.LogAsync(
            action: "platform.tenant.updated",
            targetType: "Tenant",
            targetId: tenant.Id.ToString(),
            targetTenantId: tenant.Code,
            metadata: new { tenant.Code, tenant.Name, tenant.IsActive },
            cancellationToken);

        return Ok(new
        {
            tenant.Id,
            tenant.Code,
            tenant.Name,
            tenant.IsActive,
            tenant.CreatedAtUtc
        });
    }
}
