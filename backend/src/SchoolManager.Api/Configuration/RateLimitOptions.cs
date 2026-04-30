using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Configuration;

public sealed class RateLimitOptions
{
    public const string SectionName = "RateLimit";

    [Range(10, 5000)]
    public int GlobalPermitLimit { get; init; } = 300;

    [Range(1, 60)]
    public int GlobalWindowSeconds { get; init; } = 60;

    [Range(3, 100)]
    public int AuthPermitLimit { get; init; } = 12;

    [Range(1, 300)]
    public int AuthWindowSeconds { get; init; } = 60;
}
