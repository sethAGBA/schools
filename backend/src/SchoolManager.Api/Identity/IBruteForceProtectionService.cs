namespace SchoolManager.Api.Identity;

public interface IBruteForceProtectionService
{
    Task<LockoutCheckResult> CheckLockoutAsync(
        string tenantId,
        string email,
        string? ipAddress,
        CancellationToken cancellationToken = default);

    Task RegisterAttemptAsync(
        string tenantId,
        string email,
        string? ipAddress,
        bool succeeded,
        CancellationToken cancellationToken = default);
}

public sealed record LockoutCheckResult(bool IsLocked, DateTimeOffset? LockedUntilUtc);
