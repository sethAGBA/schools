namespace SchoolManager.Modules.Tenancy.Abstractions;

public interface ITenantProvider
{
    string? GetCurrentTenantId();
}
