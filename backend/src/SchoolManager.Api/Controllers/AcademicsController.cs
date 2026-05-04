using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Api.Academics;
using SchoolManager.Modules.Academics;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/academics")]
[Authorize(Policy = "StaffOrAdmin")]
public sealed class AcademicsController(SchoolDbContext dbContext, IAuditLogger auditLogger) : ControllerBase
{
    // --- Classes ---

    [HttpGet("classes")]
    public async Task<IActionResult> ListClasses(
        [FromQuery] string? academicYear,
        [FromQuery] string? level,
        CancellationToken cancellationToken)
    {
        var query = dbContext.Classes.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(academicYear))
        {
            query = query.Where(x => x.AcademicYear == academicYear.Trim());
        }

        if (!string.IsNullOrWhiteSpace(level))
        {
            query = query.Where(x => x.Level == level.Trim());
        }

        var classes = await query
            .OrderByDescending(x => x.AcademicYear)
            .ThenBy(x => x.Name)
            .ToListAsync(cancellationToken);

        return Ok(classes);
    }

    [HttpPost("classes")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> CreateClass([FromBody] CreateClassRequest request, CancellationToken cancellationToken)
    {
        var classRoom = new ClassRoom
        {
            Name = request.Name.Trim(),
            AcademicYear = request.AcademicYear.Trim(),
            Level = request.Level?.Trim(),
            Capacity = request.Capacity
        };

        dbContext.Classes.Add(classRoom);
        await dbContext.SaveChangesAsync(cancellationToken);

        await auditLogger.LogAsync(
            action: "academics.class_created",
            targetType: "ClassRoom",
            targetId: classRoom.Id.ToString(),
            targetTenantId: classRoom.TenantId,
            metadata: new { classRoom.Name, classRoom.AcademicYear },
            cancellationToken);

        return CreatedAtAction(nameof(ListClasses), new { academicYear = classRoom.AcademicYear }, classRoom);
    }

    // --- Subjects ---

    [HttpGet("subjects")]
    public async Task<IActionResult> ListSubjects([FromQuery] Guid classId, CancellationToken cancellationToken)
    {
        var subjects = await dbContext.Subjects
            .AsNoTracking()
            .Where(x => x.ClassRoomId == classId)
            .OrderBy(x => x.Name)
            .ToListAsync(cancellationToken);

        return Ok(subjects);
    }

    [HttpPost("subjects")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> CreateSubject([FromBody] CreateSubjectRequest request, CancellationToken cancellationToken)
    {
        var classExists = await dbContext.Classes.AnyAsync(x => x.Id == request.ClassRoomId, cancellationToken);
        if (!classExists)
        {
            return BadRequest(new { error = "La classe spécifiée n'existe pas." });
        }

        var subject = new Subject
        {
            Name = request.Name.Trim(),
            Coefficient = request.Coefficient,
            ClassRoomId = request.ClassRoomId
        };

        dbContext.Subjects.Add(subject);
        await dbContext.SaveChangesAsync(cancellationToken);

        await auditLogger.LogAsync(
            action: "academics.subject_created",
            targetType: "Subject",
            targetId: subject.Id.ToString(),
            targetTenantId: subject.TenantId,
            metadata: new { subject.Name, subject.ClassRoomId },
            cancellationToken);

        return Ok(subject);
    }

    // --- Grades ---

    [HttpGet("grades")]
    public async Task<IActionResult> ListGrades(
        [FromQuery] Guid? studentId,
        [FromQuery] Guid? subjectId,
        [FromQuery] string? period,
        CancellationToken cancellationToken)
    {
        var query = dbContext.Grades.AsNoTracking();

        if (studentId.HasValue)
        {
            query = query.Where(x => x.StudentId == studentId.Value);
        }

        if (subjectId.HasValue)
        {
            query = query.Where(x => x.SubjectId == subjectId.Value);
        }

        if (!string.IsNullOrWhiteSpace(period))
        {
            query = query.Where(x => x.Period == period.Trim());
        }

        var grades = await query.ToListAsync(cancellationToken);
        return Ok(grades);
    }

    [HttpPost("grades/bulk")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> BulkUpsertGrades([FromBody] BulkUpdateGradesRequest request, CancellationToken cancellationToken)
    {
        if (request.Grades == null || request.Grades.Count == 0)
        {
            return BadRequest(new { error = "Aucune note fournie." });
        }

        var studentIds = request.Grades.Select(x => x.StudentId).Distinct().ToList();
        var subjectIds = request.Grades.Select(x => x.SubjectId).Distinct().ToList();
        var periods = request.Grades.Select(x => x.Period).Distinct().ToList();

        // Get existing grades to update if present
        var existingGrades = await dbContext.Grades
            .Where(x => studentIds.Contains(x.StudentId) && subjectIds.Contains(x.SubjectId) && periods.Contains(x.Period))
            .ToListAsync(cancellationToken);

        var countUpdated = 0;
        var countCreated = 0;

        foreach (var req in request.Grades)
        {
            var existing = existingGrades.FirstOrDefault(x => 
                x.StudentId == req.StudentId && 
                x.SubjectId == req.SubjectId && 
                x.Period == req.Period);

            if (existing != null)
            {
                existing.DevoirNote = req.DevoirNote;
                existing.CompositionNote = req.CompositionNote;
                existing.Average = req.Average;
                existing.TeacherComment = req.TeacherComment;
                existing.ClassAverage = req.ClassAverage;
                countUpdated++;
            }
            else
            {
                var grade = new Grade
                {
                    StudentId = req.StudentId,
                    SubjectId = req.SubjectId,
                    Period = req.Period,
                    DevoirNote = req.DevoirNote,
                    CompositionNote = req.CompositionNote,
                    Average = req.Average,
                    TeacherComment = req.TeacherComment,
                    ClassAverage = req.ClassAverage
                };
                dbContext.Grades.Add(grade);
                countCreated++;
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);

        await auditLogger.LogAsync(
            action: "academics.grades_bulk_upsert",
            targetType: "Grade",
            targetId: "multiple",
            targetTenantId: "context",
            metadata: new { countCreated, countUpdated },
            cancellationToken);

        return Ok(new { message = "Notes traitées avec succès.", created = countCreated, updated = countUpdated });
    }
}
