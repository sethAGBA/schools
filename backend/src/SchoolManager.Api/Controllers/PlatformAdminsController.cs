using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Api.Identity;
using SchoolManager.Api.PlatformUsers;
using SchoolManager.Modules.Identity.Domain;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/platform/admins")]
[Authorize(Policy = "SuperAdminOnly")]
public sealed class PlatformAdminsController(
    SchoolDbContext dbContext,
    IPasswordHasher passwordHasher,
    IAuditLogger auditLogger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] string? tenantCode, CancellationToken cancellationToken)
    {
        var query = dbContext.Users
            .IgnoreQueryFilters()
            .Where(x => x.Role == RoleNames.Admin);

        if (!string.IsNullOrWhiteSpace(tenantCode))
        {
            var code = tenantCode.Trim().ToLowerInvariant();
            query = query.Where(x => x.TenantId == code);
        }

        var admins = await query
            .OrderBy(x => x.TenantId)
            .ThenBy(x => x.Email)
            .Select(x => new
            {
                x.Id,
                x.TenantId,
                x.Email,
                x.Role,
                x.IsActive,
                x.CreatedAtUtc
            })
            .ToListAsync(cancellationToken);

        return Ok(admins);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateSchoolAdminRequest request, CancellationToken cancellationToken)
    {
        var tenantCode = request.TenantCode.Trim().ToLowerInvariant();
        var email = request.Email.Trim().ToLowerInvariant();

        var tenant = await dbContext.Tenants.SingleOrDefaultAsync(x => x.Code == tenantCode, cancellationToken);
        if (tenant is null)
        {
            return NotFound(new { error = "Tenant introuvable." });
        }

        if (!tenant.IsActive)
        {
            return Conflict(new { error = "Le tenant est inactif." });
        }

        var exists = await dbContext.Users
            .IgnoreQueryFilters()
            .AnyAsync(x => x.TenantId == tenantCode && x.Email == email, cancellationToken);
        if (exists)
        {
            return Conflict(new { error = "Un utilisateur avec cet email existe deja pour ce tenant." });
        }

        var admin = new AppUser
        {
            TenantId = tenantCode,
            Email = email,
            PasswordHash = passwordHasher.Hash(request.Password),
            Role = RoleNames.Admin,
            IsActive = true
        };

        dbContext.Users.Add(admin);
        await dbContext.SaveChangesAsync(cancellationToken);
        await auditLogger.LogAsync(
            action: "platform.admin.created",
            targetType: "User",
            targetId: admin.Id.ToString(),
            targetTenantId: admin.TenantId,
            metadata: new { admin.Email, admin.Role, admin.IsActive },
            cancellationToken);

        return CreatedAtAction(nameof(GetById), new { id = admin.Id }, new
        {
            admin.Id,
            admin.TenantId,
            admin.Email,
            admin.Role,
            admin.IsActive,
            admin.CreatedAtUtc
        });
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, CancellationToken cancellationToken)
    {
        var admin = await dbContext.Users
            .IgnoreQueryFilters()
            .SingleOrDefaultAsync(x => x.Id == id && x.Role == RoleNames.Admin, cancellationToken);

        if (admin is null)
        {
            return NotFound(new { error = "Admin introuvable." });
        }

        return Ok(new
        {
            admin.Id,
            admin.TenantId,
            admin.Email,
            admin.Role,
            admin.IsActive,
            admin.CreatedAtUtc
        });
    }

    [HttpPatch("{id:guid}/status")]
    public async Task<IActionResult> UpdateStatus(
        Guid id,
        [FromBody] UpdateSchoolAdminStatusRequest request,
        CancellationToken cancellationToken)
    {
        var admin = await dbContext.Users
            .IgnoreQueryFilters()
            .SingleOrDefaultAsync(x => x.Id == id && x.Role == RoleNames.Admin, cancellationToken);

        if (admin is null)
        {
            return NotFound(new { error = "Admin introuvable." });
        }

        admin.IsActive = request.IsActive;
        await dbContext.SaveChangesAsync(cancellationToken);
        await auditLogger.LogAsync(
            action: "platform.admin.status.updated",
            targetType: "User",
            targetId: admin.Id.ToString(),
            targetTenantId: admin.TenantId,
            metadata: new { admin.Email, admin.IsActive },
            cancellationToken);

        return Ok(new
        {
            admin.Id,
            admin.TenantId,
            admin.Email,
            admin.Role,
            admin.IsActive,
            admin.CreatedAtUtc
        });
    }
}
