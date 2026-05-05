using SchoolManager.BuildingBlocks.Multitenancy;

namespace SchoolManager.Modules.Finance;

public sealed class Payment : ITenantEntity
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string TenantId { get; set; } = string.Empty;
    public Guid StudentId { get; set; }
    public string ClassName { get; set; } = string.Empty;
    public string ClassAcademicYear { get; set; } = string.Empty;
    public string? ReceiptNo { get; set; }
    public double Amount { get; set; }
    public string Date { get; set; } = string.Empty;
    public string? Comment { get; set; }
    public bool IsCancelled { get; set; }
    public string? CancelledAt { get; set; }
    public string? CancelReason { get; set; }
    public string? CancelBy { get; set; }
    public string? RecordedBy { get; set; }

    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
