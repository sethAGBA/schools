using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Modules.Staff;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/staff")]
[Authorize(Policy = "StaffOrAdmin")]
public sealed class StaffController(SchoolDbContext dbContext, IAuditLogger auditLogger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> ListStaff(
        [FromQuery] string? role,
        [FromQuery] string? department,
        CancellationToken cancellationToken)
    {
        var query = dbContext.StaffMembers.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(role))
        {
            query = query.Where(x => x.Role == role.Trim());
        }

        if (!string.IsNullOrWhiteSpace(department))
        {
            query = query.Where(x => x.Department == department.Trim());
        }

        var staff = await query
            .OrderBy(x => x.Name)
            .ToListAsync(cancellationToken);

        return Ok(staff);
    }

    [HttpPost("bulk")]
    public async Task<IActionResult> BulkUpsertStaff([FromBody] BulkUpdateStaffRequest request, CancellationToken cancellationToken)
    {
        if (request.Staff == null || request.Staff.Count == 0)
        {
            return BadRequest(new { error = "Aucun membre du personnel fourni." });
        }

        var countCreated = 0;
        var countUpdated = 0;

        foreach (var req in request.Staff)
        {
            var existing = await dbContext.StaffMembers
                .FirstOrDefaultAsync(x => x.Id == req.Id, cancellationToken);

            if (existing != null)
            {
                existing.Name = req.Name;
                existing.Role = req.Role;
                existing.Department = req.Department ?? existing.Department;
                existing.Phone = req.Phone ?? existing.Phone;
                existing.Email = req.Email ?? existing.Email;
                existing.Qualifications = req.Qualifications;
                existing.Courses = req.Courses;
                existing.Classes = req.Classes;
                existing.Status = req.Status;
                existing.HireDate = req.HireDate;
                existing.TypeRole = req.TypeRole;
                
                existing.FirstName = req.FirstName;
                existing.LastName = req.LastName;
                existing.Gender = req.Gender;
                existing.BirthDate = req.BirthDate;
                existing.BirthPlace = req.BirthPlace;
                existing.Nationality = req.Nationality;
                existing.Address = req.Address;
                existing.PhotoPath = req.PhotoPath;
                
                existing.Matricule = req.Matricule;
                existing.IdNumber = req.IdNumber;
                existing.SocialSecurityNumber = req.SocialSecurityNumber;
                existing.MaritalStatus = req.MaritalStatus;
                existing.NumberOfChildren = req.NumberOfChildren;
                
                existing.Region = req.Region;
                existing.Levels = req.Levels;
                existing.HighestDegree = req.HighestDegree;
                existing.Specialty = req.Specialty;
                existing.ExperienceYears = req.ExperienceYears;
                existing.PreviousInstitution = req.PreviousInstitution;
                
                existing.ContractType = req.ContractType;
                existing.BaseSalary = req.BaseSalary;
                existing.WeeklyHours = req.WeeklyHours;
                existing.Supervisor = req.Supervisor;
                existing.RetirementDate = req.RetirementDate;
                existing.Documents = req.Documents;

                countUpdated++;
            }
            else
            {
                var staff = new StaffMember
                {
                    Id = req.Id,
                    Name = req.Name,
                    Role = req.Role,
                    Department = req.Department ?? string.Empty,
                    Phone = req.Phone ?? string.Empty,
                    Email = req.Email ?? string.Empty,
                    Qualifications = req.Qualifications,
                    Courses = req.Courses,
                    Classes = req.Classes,
                    Status = req.Status,
                    HireDate = req.HireDate,
                    TypeRole = req.TypeRole,
                    FirstName = req.FirstName,
                    LastName = req.LastName,
                    Gender = req.Gender,
                    BirthDate = req.BirthDate,
                    BirthPlace = req.BirthPlace,
                    Nationality = req.Nationality,
                    Address = req.Address,
                    PhotoPath = req.PhotoPath,
                    Matricule = req.Matricule,
                    IdNumber = req.IdNumber,
                    SocialSecurityNumber = req.SocialSecurityNumber,
                    MaritalStatus = req.MaritalStatus,
                    NumberOfChildren = req.NumberOfChildren,
                    Region = req.Region,
                    Levels = req.Levels,
                    HighestDegree = req.HighestDegree,
                    Specialty = req.Specialty,
                    ExperienceYears = req.ExperienceYears,
                    PreviousInstitution = req.PreviousInstitution,
                    ContractType = req.ContractType,
                    BaseSalary = req.BaseSalary,
                    WeeklyHours = req.WeeklyHours,
                    Supervisor = req.Supervisor,
                    RetirementDate = req.RetirementDate,
                    Documents = req.Documents
                };
                dbContext.StaffMembers.Add(staff);
                countCreated++;
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);

        await auditLogger.LogAsync(
            action: "staff.bulk_upsert",
            targetType: "Staff",
            targetId: "multiple",
            targetTenantId: "context",
            metadata: new { countCreated, countUpdated },
            cancellationToken);

        return Ok(new { message = "Personnel traité avec succès.", created = countCreated, updated = countUpdated });
    }
}

public class BulkUpdateStaffRequest
{
    public List<StaffDto> Staff { get; set; } = new();
}

public class StaffDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public string? Department { get; set; }
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string? Qualifications { get; set; }
    public string? Courses { get; set; }
    public string? Classes { get; set; }
    public string Status { get; set; } = "Actif";
    public string HireDate { get; set; } = string.Empty;
    public string TypeRole { get; set; } = "Administration";
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
    public string? Gender { get; set; }
    public string? BirthDate { get; set; }
    public string? BirthPlace { get; set; }
    public string? Nationality { get; set; }
    public string? Address { get; set; }
    public string? PhotoPath { get; set; }
    public string? Matricule { get; set; }
    public string? IdNumber { get; set; }
    public string? SocialSecurityNumber { get; set; }
    public string? MaritalStatus { get; set; }
    public int? NumberOfChildren { get; set; }
    public string? Region { get; set; }
    public string? Levels { get; set; }
    public string? HighestDegree { get; set; }
    public string? Specialty { get; set; }
    public int? ExperienceYears { get; set; }
    public string? PreviousInstitution { get; set; }
    public string? ContractType { get; set; }
    public double? BaseSalary { get; set; }
    public int? WeeklyHours { get; set; }
    public string? Supervisor { get; set; }
    public string? RetirementDate { get; set; }
    public string? Documents { get; set; }
}
