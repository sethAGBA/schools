using SchoolManager.BuildingBlocks.Multitenancy;

namespace SchoolManager.Modules.Academics;

public sealed class Grade : ITenantEntity
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string TenantId { get; set; } = string.Empty;
    public Guid StudentId { get; set; }
    public Guid SubjectId { get; set; }
    public string Period { get; set; } = string.Empty; // e.g., "Trimestre 1"
    public double? DevoirNote { get; set; }
    public double? CompositionNote { get; set; }
    public double? Average { get; set; }
    public string? TeacherComment { get; set; }
    public double? ClassAverage { get; set; }

    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
