using SchoolManager.BuildingBlocks.Multitenancy;

namespace SchoolManager.Modules.Finance;

public sealed class Expense : ITenantEntity
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string TenantId { get; set; } = string.Empty;
    public string Label { get; set; } = string.Empty;
    public string? Category { get; set; }
    public int? SupplierId { get; set; }
    public string? Supplier { get; set; }
    public double Amount { get; set; }
    public string Date { get; set; } = string.Empty;
    public string? ClassName { get; set; }
    public string AcademicYear { get; set; } = string.Empty;

    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
