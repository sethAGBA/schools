using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SchoolManager.Api.Configuration;
using SchoolManager.Api.Identity;
using SchoolManager.Modules.Identity.Domain;

namespace SchoolManager.Api.Data;

public sealed class DbInitializer(
    IServiceScopeFactory scopeFactory,
    IOptions<SeedOptions> seedOptions,
    IPasswordHasher passwordHasher,
    ILogger<DbInitializer> logger) : IHostedService
{
    private readonly SeedOptions _seedOptions = seedOptions.Value;

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        using var scope = scopeFactory.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<SchoolDbContext>();

        await dbContext.Database.MigrateAsync(cancellationToken);
        await EnsureTenantAsync(dbContext, _seedOptions.PlatformTenantId, "Platform", cancellationToken);
        await EnsureTenantAsync(dbContext, _seedOptions.SchoolTenantId, "Demo School", cancellationToken);

        await EnsureUserAsync(
            dbContext,
            _seedOptions.PlatformTenantId,
            _seedOptions.SuperAdminEmail,
            _seedOptions.SuperAdminPassword,
            RoleNames.SuperAdmin,
            cancellationToken);

        await EnsureUserAsync(
            dbContext,
            _seedOptions.SchoolTenantId,
            _seedOptions.SchoolAdminEmail,
            _seedOptions.SchoolAdminPassword,
            RoleNames.Admin,
            cancellationToken);
    }

    private static async Task EnsureTenantAsync(
        SchoolDbContext dbContext,
        string tenantCode,
        string tenantName,
        CancellationToken cancellationToken)
    {
        var code = tenantCode.Trim().ToLowerInvariant();
        var exists = await dbContext.Tenants.AnyAsync(x => x.Code == code, cancellationToken);
        if (exists)
        {
            return;
        }

        dbContext.Tenants.Add(new Modules.Tenancy.Tenant
        {
            Code = code,
            Name = tenantName,
            IsActive = true
        });

        await dbContext.SaveChangesAsync(cancellationToken);
    }

    private async Task EnsureUserAsync(
        SchoolDbContext dbContext,
        string tenantId,
        string emailInput,
        string password,
        string role,
        CancellationToken cancellationToken)
    {
        var email = emailInput.Trim().ToLowerInvariant();
        var existingUser = await dbContext.Users
            .IgnoreQueryFilters()
            .SingleOrDefaultAsync(
                x => x.TenantId == tenantId && x.Email == email,
                cancellationToken);

        if (existingUser is not null)
        {
            return;
        }

        dbContext.Users.Add(new AppUser
        {
            TenantId = tenantId,
            Email = email,
            PasswordHash = passwordHasher.Hash(password),
            Role = role,
            IsActive = true
        });

        await dbContext.SaveChangesAsync(cancellationToken);
        logger.LogInformation("Seeded user with role {Role} for tenant {TenantId}", role, tenantId);
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
