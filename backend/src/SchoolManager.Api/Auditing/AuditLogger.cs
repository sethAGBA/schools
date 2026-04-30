using System.Security.Claims;
using System.Text.Json;
using SchoolManager.Api.Data;
using SchoolManager.Modules.Audit;

namespace SchoolManager.Api.Auditing;

public sealed class AuditLogger(SchoolDbContext dbContext, IHttpContextAccessor httpContextAccessor) : IAuditLogger
{
    public async Task LogAsync(
        string action,
        string targetType,
        string? targetId,
        string? targetTenantId,
        object? metadata,
        CancellationToken cancellationToken = default)
    {
        var user = httpContextAccessor.HttpContext?.User;
        var actorUserIdValue = user?.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? user?.FindFirst("sub")?.Value;
        Guid? actorUserId = Guid.TryParse(actorUserIdValue, out var parsedId) ? parsedId : null;

        var entry = new AuditLog
        {
            ActorUserId = actorUserId,
            ActorEmail = user?.FindFirst("email")?.Value,
            ActorRole = user?.FindFirst(ClaimTypes.Role)?.Value,
            Action = action,
            TargetType = targetType,
            TargetId = targetId,
            TargetTenantId = targetTenantId,
            MetadataJson = metadata is null ? null : JsonSerializer.Serialize(metadata)
        };

        dbContext.AuditLogs.Add(entry);
        await dbContext.SaveChangesAsync(cancellationToken);
    }
}
