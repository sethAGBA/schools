using SchoolManager.BuildingBlocks.Multitenancy;

namespace SchoolManager.Modules.Identity.Domain;

public sealed class AppUser : ITenantEntity
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string TenantId { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public string Role { get; set; } = "User";
    public bool IsActive { get; set; } = true;
    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
    public List<RefreshToken> RefreshTokens { get; set; } = [];
}
