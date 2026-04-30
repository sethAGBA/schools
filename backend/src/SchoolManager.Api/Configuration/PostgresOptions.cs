using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Configuration;

public sealed class PostgresOptions
{
    public const string SectionName = "Postgres";

    [Required]
    [MinLength(10)]
    public string ConnectionString { get; init; } = string.Empty;
}
