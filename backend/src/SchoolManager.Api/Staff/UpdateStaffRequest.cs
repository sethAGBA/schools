using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Staff;

public sealed class UpdateStaffRequest
{
    // --- Required fields ---

    [Required]
    [MinLength(1)]
    [MaxLength(200)]
    public string Name { get; init; } = string.Empty;

    [Required]
    [MinLength(1)]
    [MaxLength(100)]
    public string Role { get; init; } = string.Empty;

    [Required]
    [MinLength(1)]
    [MaxLength(50)]
    public string HireDate { get; init; } = string.Empty;

    [Required]
    [MinLength(1)]
    [MaxLength(100)]
    public string TypeRole { get; init; } = string.Empty;

    [Required]
    [MinLength(1)]
    [MaxLength(50)]
    public string Status { get; init; } = string.Empty;

    // --- Optional fields ---

    [MaxLength(150)]
    public string? Department { get; init; }

    [MaxLength(60)]
    public string? Phone { get; init; }

    [EmailAddress]
    [MaxLength(320)]
    public string? Email { get; init; }

    public string? Qualifications { get; init; }

    /// <summary>Comma-separated course names.</summary>
    public string? Courses { get; init; }

    /// <summary>Comma-separated class names.</summary>
    public string? Classes { get; init; }

    [MaxLength(150)]
    public string? FirstName { get; init; }

    [MaxLength(150)]
    public string? LastName { get; init; }

    [MaxLength(30)]
    public string? Gender { get; init; }

    [MaxLength(50)]
    public string? BirthDate { get; init; }

    [MaxLength(150)]
    public string? BirthPlace { get; init; }

    [MaxLength(100)]
    public string? Nationality { get; init; }

    [MaxLength(500)]
    public string? Address { get; init; }

    [MaxLength(500)]
    public string? PhotoPath { get; init; }

    [MaxLength(100)]
    public string? Matricule { get; init; }

    [MaxLength(100)]
    public string? IdNumber { get; init; }

    [MaxLength(100)]
    public string? SocialSecurityNumber { get; init; }

    [MaxLength(50)]
    public string? MaritalStatus { get; init; }

    public int? NumberOfChildren { get; init; }

    [MaxLength(150)]
    public string? Region { get; init; }

    /// <summary>Comma-separated levels.</summary>
    public string? Levels { get; init; }

    [MaxLength(200)]
    public string? HighestDegree { get; init; }

    [MaxLength(200)]
    public string? Specialty { get; init; }

    public int? ExperienceYears { get; init; }

    [MaxLength(300)]
    public string? PreviousInstitution { get; init; }

    [MaxLength(100)]
    public string? ContractType { get; init; }

    public double? BaseSalary { get; init; }

    public int? WeeklyHours { get; init; }

    [MaxLength(200)]
    public string? Supervisor { get; init; }

    [MaxLength(50)]
    public string? RetirementDate { get; init; }

    /// <summary>Comma-separated document paths.</summary>
    public string? Documents { get; init; }
}
