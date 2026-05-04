using SchoolManager.BuildingBlocks.Multitenancy;

namespace SchoolManager.Modules.Academics;

public sealed class Subject : ITenantEntity
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string TenantId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public double Coefficient { get; set; } = 1.0;
    public Guid ClassRoomId { get; set; }
    
    // Navigation property (optional, but useful if we add it to DbContext)
    // public ClassRoom? ClassRoom { get; set; }

    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
