using System.ComponentModel.DataAnnotations;
using SchoolManager.BuildingBlocks.Multitenancy;

namespace SchoolManager.Modules.Staff;

public sealed class StaffMember : ITenantEntity
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();
    public string TenantId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public string Phone { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string? Qualifications { get; set; }
    public string? Courses { get; set; } // Comma-separated
    public string? Classes { get; set; } // Comma-separated
    public string Status { get; set; } = "Actif";
    public string HireDate { get; set; } = string.Empty;
    public string TypeRole { get; set; } = "Administration";

    // Detailed Info
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
    public string? Gender { get; set; }
    public string? BirthDate { get; set; }
    public string? BirthPlace { get; set; }
    public string? Nationality { get; set; }
    public string? Address { get; set; }
    public string? PhotoPath { get; set; }

    // Admin Identifiers
    public string? Matricule { get; set; }
    public string? IdNumber { get; set; }
    public string? SocialSecurityNumber { get; set; }
    public string? MaritalStatus { get; set; }
    public int? NumberOfChildren { get; set; }

    // Professional / Extra
    public string? Region { get; set; }
    public string? Levels { get; set; } // Comma-separated
    public string? HighestDegree { get; set; }
    public string? Specialty { get; set; }
    public int? ExperienceYears { get; set; }
    public string? PreviousInstitution { get; set; }

    // Contract
    public string? ContractType { get; set; }
    public double? BaseSalary { get; set; }
    public int? WeeklyHours { get; set; }
    public string? Supervisor { get; set; }
    public string? RetirementDate { get; set; }

    // Documents
    public string? Documents { get; set; } // Comma-separated paths

    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
