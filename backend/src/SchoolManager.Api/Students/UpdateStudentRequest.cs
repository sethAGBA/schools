using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Students;

public sealed class UpdateStudentRequest
{
    [Required]
    [MinLength(1)]
    [MaxLength(150)]
    public string FirstName { get; init; } = string.Empty;

    [Required]
    [MinLength(1)]
    [MaxLength(150)]
    public string LastName { get; init; } = string.Empty;

    [Required]
    public DateTime DateOfBirth { get; init; }

    [Required]
    [MaxLength(30)]
    public string Gender { get; init; } = string.Empty;

    [Required]
    [MaxLength(120)]
    public string ClassName { get; init; } = string.Empty;

    [Required]
    [MaxLength(40)]
    public string AcademicYear { get; init; } = string.Empty;

    [Required]
    [MaxLength(200)]
    public string GuardianName { get; init; } = string.Empty;

    [Required]
    [MaxLength(60)]
    public string GuardianContact { get; init; } = string.Empty;

    [Required]
    [MaxLength(60)]
    public string ContactNumber { get; init; } = string.Empty;

    [EmailAddress]
    [MaxLength(320)]
    public string? Email { get; init; }

    [MaxLength(500)]
    public string? Address { get; init; }

    public bool IsActive { get; init; } = true;
}
