using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Api.Students;
using SchoolManager.Modules.Students;
using System.Text.RegularExpressions;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/students")]
[Authorize(Policy = "StaffOrAdmin")]
public sealed class StudentsController(SchoolDbContext dbContext, IAuditLogger auditLogger) : ControllerBase
{
    private static readonly Regex AcademicYearRegex = new(@"^\d{4}-\d{4}$", RegexOptions.Compiled);
    private static readonly HashSet<string> AllowedGenders = new(StringComparer.OrdinalIgnoreCase) { "M", "F" };

    [HttpGet]
    public async Task<IActionResult> List(
        [FromQuery] string? className,
        [FromQuery] string? academicYear,
        [FromQuery] string? search,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken cancellationToken = default)
    {
        var boundedPage = Math.Max(page, 1);
        var boundedPageSize = Math.Clamp(pageSize, 1, 200);
        var query = dbContext.Students.AsNoTracking().Where(x => x.IsActive);

        if (!string.IsNullOrWhiteSpace(className))
        {
            var normalizedClass = className.Trim();
            query = query.Where(x => x.ClassName == normalizedClass);
        }

        if (!string.IsNullOrWhiteSpace(academicYear))
        {
            var normalizedYear = academicYear.Trim();
            query = query.Where(x => x.AcademicYear == normalizedYear);
        }

        if (!string.IsNullOrWhiteSpace(search))
        {
            var normalizedSearch = search.Trim().ToLowerInvariant();
            query = query.Where(x =>
                x.FirstName.ToLower().Contains(normalizedSearch) ||
                x.LastName.ToLower().Contains(normalizedSearch) ||
                (x.Email != null && x.Email.ToLower().Contains(normalizedSearch)));
        }

        var total = await query.CountAsync(cancellationToken);
        var students = await query
            .OrderBy(x => x.LastName)
            .ThenBy(x => x.FirstName)
            .Skip((boundedPage - 1) * boundedPageSize)
            .Take(boundedPageSize)
            .Select(x => new
            {
                x.Id,
                x.FirstName,
                x.LastName,
                x.DateOfBirth,
                x.Gender,
                x.ClassName,
                x.AcademicYear,
                x.GuardianName,
                x.GuardianContact,
                x.ContactNumber,
                x.Email,
                x.Address,
                x.IsActive,
                x.CreatedAtUtc,
                x.UpdatedAtUtc
            })
            .ToListAsync(cancellationToken);

        return Ok(new
        {
            items = students,
            total,
            page = boundedPage,
            pageSize = boundedPageSize
        });
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, CancellationToken cancellationToken)
    {
        var student = await dbContext.Students.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id, cancellationToken);
        if (student is null)
        {
            return NotFound(new { error = "Eleve introuvable." });
        }

        return Ok(new
        {
            student.Id,
            student.FirstName,
            student.LastName,
            student.DateOfBirth,
            student.Gender,
            student.ClassName,
            student.AcademicYear,
            student.GuardianName,
            student.GuardianContact,
            student.ContactNumber,
            student.Email,
            student.Address,
            student.IsActive,
            student.CreatedAtUtc,
            student.UpdatedAtUtc
        });
    }

    [HttpPost]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> Create([FromBody] CreateStudentRequest request, CancellationToken cancellationToken)
    {
        var validationError = ValidateStudentRequest(request);
        if (validationError is not null)
        {
            return BadRequest(new { error = validationError });
        }

        var student = new StudentRecord
        {
            FirstName = request.FirstName.Trim(),
            LastName = request.LastName.Trim(),
            DateOfBirth = request.DateOfBirth.Date,
            Gender = request.Gender.Trim(),
            ClassName = request.ClassName.Trim(),
            AcademicYear = request.AcademicYear.Trim(),
            GuardianName = request.GuardianName.Trim(),
            GuardianContact = request.GuardianContact.Trim(),
            ContactNumber = request.ContactNumber.Trim(),
            Email = string.IsNullOrWhiteSpace(request.Email) ? null : request.Email.Trim().ToLowerInvariant(),
            Address = string.IsNullOrWhiteSpace(request.Address) ? null : request.Address.Trim(),
            IsActive = true
        };

        dbContext.Students.Add(student);
        await dbContext.SaveChangesAsync(cancellationToken);
        await auditLogger.LogAsync(
            action: "students.created",
            targetType: "Student",
            targetId: student.Id.ToString(),
            targetTenantId: student.TenantId,
            metadata: new { student.FirstName, student.LastName, student.ClassName, student.AcademicYear },
            cancellationToken);

        return CreatedAtAction(nameof(GetById), new { id = student.Id }, new
        {
            student.Id,
            student.FirstName,
            student.LastName,
            student.DateOfBirth,
            student.Gender,
            student.ClassName,
            student.AcademicYear,
            student.GuardianName,
            student.GuardianContact,
            student.ContactNumber,
            student.Email,
            student.Address,
            student.IsActive,
            student.CreatedAtUtc,
            student.UpdatedAtUtc
        });
    }

    [HttpPut("{id:guid}")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateStudentRequest request, CancellationToken cancellationToken)
    {
        var validationError = ValidateStudentRequest(request);
        if (validationError is not null)
        {
            return BadRequest(new { error = validationError });
        }

        var student = await dbContext.Students.SingleOrDefaultAsync(x => x.Id == id, cancellationToken);
        if (student is null)
        {
            return NotFound(new { error = "Eleve introuvable." });
        }

        student.FirstName = request.FirstName.Trim();
        student.LastName = request.LastName.Trim();
        student.DateOfBirth = request.DateOfBirth.Date;
        student.Gender = request.Gender.Trim();
        student.ClassName = request.ClassName.Trim();
        student.AcademicYear = request.AcademicYear.Trim();
        student.GuardianName = request.GuardianName.Trim();
        student.GuardianContact = request.GuardianContact.Trim();
        student.ContactNumber = request.ContactNumber.Trim();
        student.Email = string.IsNullOrWhiteSpace(request.Email) ? null : request.Email.Trim().ToLowerInvariant();
        student.Address = string.IsNullOrWhiteSpace(request.Address) ? null : request.Address.Trim();
        student.IsActive = request.IsActive;

        await dbContext.SaveChangesAsync(cancellationToken);
        await auditLogger.LogAsync(
            action: "students.updated",
            targetType: "Student",
            targetId: student.Id.ToString(),
            targetTenantId: student.TenantId,
            metadata: new { student.FirstName, student.LastName, student.ClassName, student.AcademicYear, student.IsActive },
            cancellationToken);

        return Ok(new
        {
            student.Id,
            student.FirstName,
            student.LastName,
            student.DateOfBirth,
            student.Gender,
            student.ClassName,
            student.AcademicYear,
            student.GuardianName,
            student.GuardianContact,
            student.ContactNumber,
            student.Email,
            student.Address,
            student.IsActive,
            student.CreatedAtUtc,
            student.UpdatedAtUtc
        });
    }

    [HttpDelete("{id:guid}")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken cancellationToken)
    {
        var student = await dbContext.Students.SingleOrDefaultAsync(x => x.Id == id, cancellationToken);
        if (student is null)
        {
            return NotFound(new { error = "Eleve introuvable." });
        }

        if (!student.IsActive)
        {
            return NoContent();
        }

        student.IsActive = false;
        await dbContext.SaveChangesAsync(cancellationToken);
        await auditLogger.LogAsync(
            action: "students.deleted",
            targetType: "Student",
            targetId: student.Id.ToString(),
            targetTenantId: student.TenantId,
            metadata: new { student.FirstName, student.LastName, student.ClassName, student.AcademicYear },
            cancellationToken);
        return NoContent();
    }

    private static string? ValidateStudentRequest(CreateStudentRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.FirstName) || string.IsNullOrWhiteSpace(request.LastName))
        {
            return "Le nom et le prenom sont obligatoires.";
        }

        if (request.DateOfBirth.Date > DateTime.UtcNow.Date)
        {
            return "La date de naissance ne peut pas etre dans le futur.";
        }

        var age = DateTime.UtcNow.Year - request.DateOfBirth.Year;
        if (request.DateOfBirth.Date > DateTime.UtcNow.AddYears(-age))
        {
            age -= 1;
        }
        if (age is < 2 or > 30)
        {
            return "La date de naissance est hors plage autorisee.";
        }

        if (!AllowedGenders.Contains(request.Gender.Trim()))
        {
            return "Le genre doit etre M ou F.";
        }

        if (!AcademicYearRegex.IsMatch(request.AcademicYear.Trim()))
        {
            return "Le format de l'annee academique doit etre YYYY-YYYY.";
        }

        return null;
    }

    private static string? ValidateStudentRequest(UpdateStudentRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.FirstName) || string.IsNullOrWhiteSpace(request.LastName))
        {
            return "Le nom et le prenom sont obligatoires.";
        }

        if (request.DateOfBirth.Date > DateTime.UtcNow.Date)
        {
            return "La date de naissance ne peut pas etre dans le futur.";
        }

        var age = DateTime.UtcNow.Year - request.DateOfBirth.Year;
        if (request.DateOfBirth.Date > DateTime.UtcNow.AddYears(-age))
        {
            age -= 1;
        }
        if (age is < 2 or > 30)
        {
            return "La date de naissance est hors plage autorisee.";
        }

        if (!AllowedGenders.Contains(request.Gender.Trim()))
        {
            return "Le genre doit etre M ou F.";
        }

        if (!AcademicYearRegex.IsMatch(request.AcademicYear.Trim()))
        {
            return "Le format de l'annee academique doit etre YYYY-YYYY.";
        }

        return null;
    }
}
