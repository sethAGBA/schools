namespace SchoolManager.Api.Multitenancy;

public interface ITenantContext
{
    string? TenantId { get; set; }
}
