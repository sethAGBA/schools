namespace SchoolManager.Api.Multitenancy;

public sealed class HttpTenantContext : ITenantContext
{
    public string? TenantId { get; set; }
}
