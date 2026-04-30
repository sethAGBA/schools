using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Identity;

public sealed class RefreshRequest
{
    [Required]
    [MinLength(10)]
    public string RefreshToken { get; init; } = string.Empty;
}
