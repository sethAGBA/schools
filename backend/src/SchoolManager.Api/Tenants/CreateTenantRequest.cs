using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Tenants;

public sealed class CreateTenantRequest
{
    [Required]
    [MinLength(3)]
    [MaxLength(100)]
    public string Code { get; init; } = string.Empty;

    [Required]
    [MinLength(2)]
    [MaxLength(200)]
    public string Name { get; init; } = string.Empty;
}
