using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Configuration;

public sealed class JwtOptions
{
    public const string SectionName = "Jwt";

    [Required]
    [MinLength(32)]
    public string Issuer { get; init; } = string.Empty;

    [Required]
    [MinLength(32)]
    public string Audience { get; init; } = string.Empty;

    [Required]
    [MinLength(32)]
    public string SigningKey { get; init; } = string.Empty;

    [Range(5, 240)]
    public int AccessTokenMinutes { get; init; } = 30;
}
