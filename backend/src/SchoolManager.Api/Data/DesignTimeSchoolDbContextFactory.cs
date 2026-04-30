using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using SchoolManager.Api.Multitenancy;

namespace SchoolManager.Api.Data;

public sealed class DesignTimeSchoolDbContextFactory : IDesignTimeDbContextFactory<SchoolDbContext>
{
    public SchoolDbContext CreateDbContext(string[] args)
    {
        var optionsBuilder = new DbContextOptionsBuilder<SchoolDbContext>();
        optionsBuilder.UseNpgsql(
            "Host=localhost;Port=5432;Database=school_manager_dev;Username=postgres;Password=postgres");

        return new SchoolDbContext(optionsBuilder.Options, new DesignTimeTenantContext());
    }

    private sealed class DesignTimeTenantContext : ITenantContext
    {
        public string? TenantId { get; set; } = "design-time";
    }
}
