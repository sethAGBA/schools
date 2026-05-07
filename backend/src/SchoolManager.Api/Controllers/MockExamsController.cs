using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Modules.Academics;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/mock-exams")]
[Authorize(Policy = "StaffOrAdmin")]
public sealed class MockExamsController(SchoolDbContext dbContext, IAuditLogger auditLogger) : ControllerBase
{
    // --- Sessions ---

    [HttpGet("sessions")]
    public async Task<IActionResult> ListSessions(CancellationToken cancellationToken)
    {
        var sessions = await dbContext.MockExamSessions
            .AsNoTracking()
            .OrderBy(x => x.OrderIndex)
            .ThenBy(x => x.Name)
            .ToListAsync(cancellationToken);

        return Ok(sessions);
    }

    [HttpPost("sessions/sync")]
    public async Task<IActionResult> SyncSessions([FromBody] List<MockExamSessionDto> sessions, CancellationToken cancellationToken)
    {
        var existingSessions = await dbContext.MockExamSessions.ToListAsync(cancellationToken);
        
        foreach (var dto in sessions)
        {
            var existing = existingSessions.FirstOrDefault(x => x.Name == dto.Name);
            if (existing != null)
            {
                existing.OrderIndex = dto.OrderIndex;
                existing.UpdatedAtUtc = DateTimeOffset.UtcNow;
            }
            else
            {
                dbContext.MockExamSessions.Add(new MockExamSession
                {
                    Name = dto.Name,
                    OrderIndex = dto.OrderIndex
                });
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        return Ok(new { message = "Sessions synchronisées." });
    }

    [HttpDelete("sessions/{name}")]
    public async Task<IActionResult> DeleteSession(string name, CancellationToken cancellationToken)
    {
        var session = await dbContext.MockExamSessions.FirstOrDefaultAsync(x => x.Name == name, cancellationToken);
        if (session == null) return NotFound();

        dbContext.MockExamSessions.Remove(session);
        await dbContext.SaveChangesAsync(cancellationToken);
        
        return NoContent();
    }

    // --- Grades ---

    [HttpPost("grades/bulk")]
    public async Task<IActionResult> BulkUpsertMockGrades([FromBody] List<MockGradeDto> grades, CancellationToken cancellationToken)
    {
        if (grades.Count == 0) return Ok();

        var studentIds = grades.Select(x => x.StudentId).Distinct().ToList();
        var subjectIds = grades.Select(x => x.SubjectId).Distinct().ToList();
        var sessions = grades.Select(x => x.Session).Distinct().ToList();

        var existingGrades = await dbContext.Grades
            .Where(x => x.Type == "Examen Blanc" && 
                        studentIds.Contains(x.StudentId) && 
                        subjectIds.Contains(x.SubjectId) && 
                        sessions.Contains(x.Period))
            .ToListAsync(cancellationToken);

        int created = 0;
        int updated = 0;

        foreach (var dto in grades)
        {
            var existing = existingGrades.FirstOrDefault(x => 
                x.StudentId == dto.StudentId && 
                x.SubjectId == dto.SubjectId && 
                x.Period == dto.Session);

            if (existing != null)
            {
                existing.Average = dto.Value; // Store mock exam note in Average
                existing.UpdatedAtUtc = DateTimeOffset.UtcNow;
                updated++;
            }
            else
            {
                dbContext.Grades.Add(new Grade
                {
                    StudentId = dto.StudentId,
                    SubjectId = dto.SubjectId,
                    Period = dto.Session,
                    Average = dto.Value,
                    Type = "Examen Blanc"
                });
                created++;
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        return Ok(new { created, updated });
    }
}

public record MockExamSessionDto(string Name, int OrderIndex);
public record MockGradeDto(Guid StudentId, Guid SubjectId, string Session, double Value);
