using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Api.Multitenancy;
using SchoolManager.Modules.Identity.Abstractions;

namespace SchoolManager.Api.Identity;

public sealed class AuthService(
    SchoolDbContext dbContext,
    ITenantContext tenantContext,
    IPasswordHasher passwordHasher,
    IJwtTokenService tokenService,
    IAuditLogger auditLogger,
    IBruteForceProtectionService bruteForceProtectionService,
    IHttpContextAccessor httpContextAccessor) : IAuthService
{
    public async Task<AuthResult> LoginAsync(
        string email,
        string password,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(tenantContext.TenantId))
        {
            await auditLogger.LogAsync(
                action: "auth.login.failed",
                targetType: "Auth",
                targetId: null,
                targetTenantId: null,
                metadata: new { reason = "tenant_missing", email },
                cancellationToken);
            return new AuthResult(false, null, null, "Tenant manquant (X-Tenant-Id).");
        }

        var normalizedEmail = email.Trim().ToLowerInvariant();
        var remoteIpAddress = httpContextAccessor.HttpContext?.Connection.RemoteIpAddress?.ToString();
        var lockoutStatus = await bruteForceProtectionService.CheckLockoutAsync(
            tenantContext.TenantId,
            normalizedEmail,
            remoteIpAddress,
            cancellationToken);

        if (lockoutStatus.IsLocked)
        {
            await auditLogger.LogAsync(
                action: "auth.login.blocked",
                targetType: "User",
                targetId: null,
                targetTenantId: tenantContext.TenantId,
                metadata: new
                {
                    reason = "bruteforce_lockout",
                    email = normalizedEmail,
                    ipAddress = remoteIpAddress,
                    lockoutUntilUtc = lockoutStatus.LockedUntilUtc
                },
                cancellationToken);
            return new AuthResult(false, null, null, "Trop de tentatives. Reessayez plus tard.");
        }

        var user = await dbContext.Users
            .SingleOrDefaultAsync(x => x.Email == normalizedEmail && x.IsActive, cancellationToken);

        if (user is null || !passwordHasher.Verify(password, user.PasswordHash))
        {
            await bruteForceProtectionService.RegisterAttemptAsync(
                tenantContext.TenantId,
                normalizedEmail,
                remoteIpAddress,
                succeeded: false,
                cancellationToken);
            await auditLogger.LogAsync(
                action: "auth.login.failed",
                targetType: "User",
                targetId: null,
                targetTenantId: tenantContext.TenantId,
                metadata: new { reason = "invalid_credentials", email = normalizedEmail, ipAddress = remoteIpAddress },
                cancellationToken);
            return new AuthResult(false, null, null, "Identifiants invalides.");
        }

        await bruteForceProtectionService.RegisterAttemptAsync(
            tenantContext.TenantId,
            normalizedEmail,
            remoteIpAddress,
            succeeded: true,
            cancellationToken);

        var accessToken = tokenService.GenerateAccessToken(user);
        var refreshToken = TokenGenerator.CreateSecureToken();
        dbContext.RefreshTokens.Add(new Modules.Identity.Domain.RefreshToken
        {
            UserId = user.Id,
            TokenHash = TokenHashing.Sha256(refreshToken),
            ExpiresAtUtc = DateTimeOffset.UtcNow.AddDays(14)
        });
        await dbContext.SaveChangesAsync(cancellationToken);
        await auditLogger.LogAsync(
            action: "auth.login.succeeded",
            targetType: "User",
            targetId: user.Id.ToString(),
            targetTenantId: user.TenantId,
            metadata: new { user.Email, user.Role },
            cancellationToken);
        return new AuthResult(true, accessToken, refreshToken, null);
    }

    public async Task<AuthResult> RefreshAsync(string refreshToken, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(tenantContext.TenantId))
        {
            await auditLogger.LogAsync(
                action: "auth.refresh.failed",
                targetType: "Auth",
                targetId: null,
                targetTenantId: null,
                metadata: new { reason = "tenant_missing" },
                cancellationToken);
            return new AuthResult(false, null, null, "Tenant manquant (X-Tenant-Id).");
        }

        var refreshTokenHash = TokenHashing.Sha256(refreshToken);
        var tokenEntry = await dbContext.RefreshTokens
            .Include(x => x.User)
            .SingleOrDefaultAsync(x => x.TokenHash == refreshTokenHash, cancellationToken);

        if (tokenEntry?.User is null ||
            !tokenEntry.User.IsActive ||
            tokenEntry.RevokedAtUtc is not null ||
            tokenEntry.ExpiresAtUtc <= DateTimeOffset.UtcNow)
        {
            await auditLogger.LogAsync(
                action: "auth.refresh.failed",
                targetType: "RefreshToken",
                targetId: null,
                targetTenantId: tenantContext.TenantId,
                metadata: new { reason = "invalid_refresh_token" },
                cancellationToken);
            return new AuthResult(false, null, null, "Refresh token invalide.");
        }

        tokenEntry.RevokedAtUtc = DateTimeOffset.UtcNow;
        var newRefreshToken = TokenGenerator.CreateSecureToken();
        dbContext.RefreshTokens.Add(new Modules.Identity.Domain.RefreshToken
        {
            UserId = tokenEntry.UserId,
            TokenHash = TokenHashing.Sha256(newRefreshToken),
            ExpiresAtUtc = DateTimeOffset.UtcNow.AddDays(14)
        });

        var newAccessToken = tokenService.GenerateAccessToken(tokenEntry.User);
        await dbContext.SaveChangesAsync(cancellationToken);
        await auditLogger.LogAsync(
            action: "auth.refresh.succeeded",
            targetType: "User",
            targetId: tokenEntry.UserId.ToString(),
            targetTenantId: tokenEntry.User.TenantId,
            metadata: new { tokenEntry.User.Email, tokenEntry.User.Role },
            cancellationToken);
        return new AuthResult(true, newAccessToken, newRefreshToken, null);
    }

    public async Task<AuthResult> LogoutAsync(string refreshToken, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(tenantContext.TenantId))
        {
            await auditLogger.LogAsync(
                action: "auth.logout.failed",
                targetType: "Auth",
                targetId: null,
                targetTenantId: null,
                metadata: new { reason = "tenant_missing" },
                cancellationToken);
            return new AuthResult(false, null, null, "Tenant manquant (X-Tenant-Id).");
        }

        var refreshTokenHash = TokenHashing.Sha256(refreshToken);
        var tokenEntry = await dbContext.RefreshTokens
            .Include(x => x.User)
            .SingleOrDefaultAsync(x => x.TokenHash == refreshTokenHash, cancellationToken);

        if (tokenEntry?.User is null || tokenEntry.RevokedAtUtc is not null)
        {
            await auditLogger.LogAsync(
                action: "auth.logout.failed",
                targetType: "RefreshToken",
                targetId: null,
                targetTenantId: tenantContext.TenantId,
                metadata: new { reason = "refresh_token_not_found_or_revoked" },
                cancellationToken);
            return new AuthResult(false, null, null, "Refresh token invalide.");
        }

        tokenEntry.RevokedAtUtc = DateTimeOffset.UtcNow;
        await dbContext.SaveChangesAsync(cancellationToken);
        await auditLogger.LogAsync(
            action: "auth.logout.succeeded",
            targetType: "User",
            targetId: tokenEntry.UserId.ToString(),
            targetTenantId: tokenEntry.User.TenantId,
            metadata: new { tokenEntry.User.Email },
            cancellationToken);

        return new AuthResult(true, null, null, null);
    }
}
