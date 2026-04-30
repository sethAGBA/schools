using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Configuration;

public sealed class SeedOptions
{
    public const string SectionName = "Seed";

    [Required]
    [MinLength(3)]
    public string SchoolTenantId { get; init; } = "demo-school";

    [Required]
    [EmailAddress]
    public string SchoolAdminEmail { get; init; } = "admin@school.local";

    [Required]
    [MinLength(8)]
    public string SchoolAdminPassword { get; init; } = "ChangeMeNow123!";

    [Required]
    [MinLength(3)]
    public string PlatformTenantId { get; init; } = "platform";

    [Required]
    [EmailAddress]
    public string SuperAdminEmail { get; init; } = "owner@platform.local";

    [Required]
    [MinLength(8)]
    public string SuperAdminPassword { get; init; } = "ChangeMeNow123!";
}
