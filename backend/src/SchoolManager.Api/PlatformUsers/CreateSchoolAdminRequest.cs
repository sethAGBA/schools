using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.PlatformUsers;

public sealed class CreateSchoolAdminRequest
{
    [Required]
    [MinLength(3)]
    [MaxLength(100)]
    public string TenantCode { get; init; } = string.Empty;

    [Required]
    [EmailAddress]
    public string Email { get; init; } = string.Empty;

    [Required]
    [MinLength(8)]
    public string Password { get; init; } = string.Empty;
}
