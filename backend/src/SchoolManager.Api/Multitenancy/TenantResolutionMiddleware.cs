namespace SchoolManager.Api.Multitenancy;

public sealed class TenantResolutionMiddleware(RequestDelegate next)
{
    private const string TenantHeader = "X-Tenant-Id";

    public async Task InvokeAsync(HttpContext context, ITenantContext tenantContext)
    {
        if (context.Request.Headers.TryGetValue(TenantHeader, out var tenantIdValues))
        {
            tenantContext.TenantId = tenantIdValues.FirstOrDefault();
        }

        await next(context);
    }
}
