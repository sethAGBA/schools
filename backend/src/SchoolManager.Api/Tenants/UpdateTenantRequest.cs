using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Tenants;

public sealed class UpdateTenantRequest
{
    [Required]
    [MinLength(2)]
    [MaxLength(200)]
    public string Name { get; init; } = string.Empty;

    public bool? IsActive { get; init; }
}
