using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Configuration;

public sealed class BruteForceOptions
{
    public const string SectionName = "BruteForce";

    [Range(3, 20)]
    public int MaxFailedAttempts { get; init; } = 5;

    [Range(1, 120)]
    public int WindowMinutes { get; init; } = 15;

    [Range(1, 240)]
    public int LockoutMinutes { get; init; } = 30;
}
