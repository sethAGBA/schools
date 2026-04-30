using SchoolManager.Api.Configuration;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Api.Identity;
using SchoolManager.Api.Multitenancy;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using SchoolManager.Modules.Identity.Abstractions;
using System.Text;
using System.Threading.RateLimiting;

var builder = WebApplication.CreateBuilder(args);

builder.Services
    .AddOptions<PostgresOptions>()
    .Bind(builder.Configuration.GetSection(PostgresOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services
    .AddOptions<JwtOptions>()
    .Bind(builder.Configuration.GetSection(JwtOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services
    .AddOptions<SeedOptions>()
    .Bind(builder.Configuration.GetSection(SeedOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services
    .AddOptions<BruteForceOptions>()
    .Bind(builder.Configuration.GetSection(BruteForceOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services
    .AddOptions<RateLimitOptions>()
    .Bind(builder.Configuration.GetSection(RateLimitOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

var jwtSection = builder.Configuration.GetSection(JwtOptions.SectionName);
var jwtIssuer = jwtSection.GetValue<string>(nameof(JwtOptions.Issuer)) ?? string.Empty;
var jwtAudience = jwtSection.GetValue<string>(nameof(JwtOptions.Audience)) ?? string.Empty;
var jwtSigningKey = jwtSection.GetValue<string>(nameof(JwtOptions.SigningKey)) ?? string.Empty;
var rateLimitSection = builder.Configuration.GetSection(RateLimitOptions.SectionName);
var globalPermitLimit = rateLimitSection.GetValue<int?>(nameof(RateLimitOptions.GlobalPermitLimit)) ?? 300;
var globalWindowSeconds = rateLimitSection.GetValue<int?>(nameof(RateLimitOptions.GlobalWindowSeconds)) ?? 60;
var authPermitLimit = rateLimitSection.GetValue<int?>(nameof(RateLimitOptions.AuthPermitLimit)) ?? 12;
var authWindowSeconds = rateLimitSection.GetValue<int?>(nameof(RateLimitOptions.AuthWindowSeconds)) ?? 60;
var allowedCorsOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwtIssuer,
            ValidAudience = jwtAudience,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSigningKey))
        };
    });

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("SuperAdminOnly", policy => policy.RequireRole(RoleNames.SuperAdmin));
    options.AddPolicy("AdminOnly", policy => policy.RequireRole(RoleNames.Admin, RoleNames.SuperAdmin));
    options.AddPolicy("StaffOrAdmin", policy => policy.RequireRole(RoleNames.Staff, RoleNames.Admin, RoleNames.SuperAdmin));
    options.AddPolicy("TeacherOrAdmin", policy => policy.RequireRole(RoleNames.Teacher, RoleNames.Admin, RoleNames.SuperAdmin));
});
builder.Services.AddCors(options =>
{
    options.AddPolicy("ApiCors", corsPolicyBuilder =>
    {
        if (allowedCorsOrigins.Length == 0)
        {
            return;
        }

        corsPolicyBuilder
            .WithOrigins(allowedCorsOrigins)
            .AllowAnyHeader()
            .AllowAnyMethod();
    });
});
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
    {
        var clientIp = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        return RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: clientIp,
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = globalPermitLimit,
                Window = TimeSpan.FromSeconds(globalWindowSeconds),
                QueueLimit = 0,
                AutoReplenishment = true
            });
    });

    options.AddPolicy("AuthPolicy", context =>
    {
        var clientIp = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        return RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: $"auth:{clientIp}",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = authPermitLimit,
                Window = TimeSpan.FromSeconds(authWindowSeconds),
                QueueLimit = 0,
                AutoReplenishment = true
            });
    });
});
builder.Services.AddHealthChecks();
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ITenantContext, HttpTenantContext>();
builder.Services.AddScoped<IPasswordHasher, Pbkdf2PasswordHasher>();
builder.Services.AddScoped<IJwtTokenService, JwtTokenService>();
builder.Services.AddScoped<IBruteForceProtectionService, BruteForceProtectionService>();
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<IAuditLogger, AuditLogger>();
builder.Services.AddDbContext<SchoolDbContext>((serviceProvider, options) =>
{
    var postgresOptions = serviceProvider
        .GetRequiredService<IOptions<PostgresOptions>>()
        .Value;

    options.UseNpgsql(postgresOptions.ConnectionString);
});
builder.Services.AddControllers();
builder.Services.AddHostedService<DbInitializer>();

var app = builder.Build();

app.UseHttpsRedirection();
if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}

var forwardedHeadersOptions = new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto | ForwardedHeaders.XForwardedHost
};
forwardedHeadersOptions.KnownIPNetworks.Clear();
forwardedHeadersOptions.KnownProxies.Clear();
app.UseForwardedHeaders(forwardedHeadersOptions);

app.Use(async (context, next) =>
{
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["X-Frame-Options"] = "DENY";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    context.Response.Headers["Permissions-Policy"] = "geolocation=(), camera=(), microphone=()";
    context.Response.Headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'";
    context.Response.Headers["X-Permitted-Cross-Domain-Policies"] = "none";
    await next();
});

app.UseCors("ApiCors");
app.UseRateLimiter();
app.UseMiddleware<TenantResolutionMiddleware>();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

app.MapGet("/", () => Results.Ok(new
{
    service = "SchoolManager.Api",
    status = "running"
}));

app.Run();
