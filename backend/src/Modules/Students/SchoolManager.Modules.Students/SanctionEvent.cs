using SchoolManager.BuildingBlocks.Multitenancy;

namespace SchoolManager.Modules.Students;

public sealed class SanctionEvent : ITenantEntity
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string TenantId { get; set; } = string.Empty;
    public string StudentId { get; set; } = string.Empty;
    public string AcademicYear { get; set; } = string.Empty;
    public string ClassName { get; set; } = string.Empty;
    public string Date { get; set; } = string.Empty; // ISO8601
    public string Type { get; set; } = string.Empty; // avertissement | blame | exclusion | autre
    public string Description { get; set; } = string.Empty;
    public string? RecordedBy { get; set; }

    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
