using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Identity;

public sealed class LogoutRequest
{
    [Required]
    [MinLength(10)]
    public string RefreshToken { get; init; } = string.Empty;
}
