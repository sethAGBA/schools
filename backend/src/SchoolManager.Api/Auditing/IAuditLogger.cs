namespace SchoolManager.Api.Auditing;

public interface IAuditLogger
{
    Task LogAsync(
        string action,
        string targetType,
        string? targetId,
        string? targetTenantId,
        object? metadata,
        CancellationToken cancellationToken = default);
}
