using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SchoolManager.Api.Configuration;
using SchoolManager.Api.Data;
using SchoolManager.Modules.Audit;

namespace SchoolManager.Api.Identity;

public sealed class BruteForceProtectionService(
    SchoolDbContext dbContext,
    IOptions<BruteForceOptions> bruteForceOptions) : IBruteForceProtectionService
{
    private readonly BruteForceOptions _options = bruteForceOptions.Value;

    public async Task<LockoutCheckResult> CheckLockoutAsync(
        string tenantId,
        string email,
        string? ipAddress,
        CancellationToken cancellationToken = default)
    {
        var normalizedTenant = tenantId.Trim().ToLowerInvariant();
        var normalizedEmail = email.Trim().ToLowerInvariant();
        var windowSince = DateTimeOffset.UtcNow.AddMinutes(-_options.WindowMinutes);

        var recentAttemptsQuery = dbContext.LoginAttempts
            .Where(x =>
                x.TenantId == normalizedTenant &&
                x.Email == normalizedEmail &&
                x.AttemptedAtUtc >= windowSince);

        if (!string.IsNullOrWhiteSpace(ipAddress))
        {
            recentAttemptsQuery = recentAttemptsQuery.Where(x => x.IpAddress == ipAddress);
        }

        var lastSuccess = await recentAttemptsQuery
            .Where(x => x.Succeeded)
            .OrderByDescending(x => x.AttemptedAtUtc)
            .Select(x => (DateTimeOffset?)x.AttemptedAtUtc)
            .FirstOrDefaultAsync(cancellationToken);

        var failedAttempts = await recentAttemptsQuery
            .Where(x => !x.Succeeded && (lastSuccess == null || x.AttemptedAtUtc > lastSuccess))
            .OrderByDescending(x => x.AttemptedAtUtc)
            .Select(x => x.AttemptedAtUtc)
            .Take(_options.MaxFailedAttempts)
            .ToListAsync(cancellationToken);

        if (failedAttempts.Count < _options.MaxFailedAttempts)
        {
            return new LockoutCheckResult(false, null);
        }

        var lastFailure = failedAttempts.Max();
        var lockedUntil = lastFailure.AddMinutes(_options.LockoutMinutes);
        return lockedUntil > DateTimeOffset.UtcNow
            ? new LockoutCheckResult(true, lockedUntil)
            : new LockoutCheckResult(false, null);
    }

    public async Task RegisterAttemptAsync(
        string tenantId,
        string email,
        string? ipAddress,
        bool succeeded,
        CancellationToken cancellationToken = default)
    {
        dbContext.LoginAttempts.Add(new LoginAttempt
        {
            TenantId = tenantId.Trim().ToLowerInvariant(),
            Email = email.Trim().ToLowerInvariant(),
            IpAddress = ipAddress,
            Succeeded = succeeded
        });

        await dbContext.SaveChangesAsync(cancellationToken);
    }
}
