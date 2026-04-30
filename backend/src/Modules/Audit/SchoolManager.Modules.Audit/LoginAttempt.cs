namespace SchoolManager.Modules.Audit;

public sealed class LoginAttempt
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string TenantId { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string? IpAddress { get; set; }
    public bool Succeeded { get; set; }
    public DateTimeOffset AttemptedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
