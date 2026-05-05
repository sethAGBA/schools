using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Modules.Students;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/discipline")]
[Authorize(Policy = "StaffOrAdmin")]
public sealed class DisciplineController(SchoolDbContext dbContext, IAuditLogger auditLogger) : ControllerBase
{
    [HttpGet("attendance")]
    public async Task<IActionResult> ListAttendance(
        [FromQuery] string? studentId,
        [FromQuery] string? academicYear,
        [FromQuery] string? className,
        CancellationToken cancellationToken)
    {
        var query = dbContext.AttendanceEvents.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(studentId))
        {
            query = query.Where(x => x.StudentId == studentId);
        }

        if (!string.IsNullOrWhiteSpace(academicYear))
        {
            query = query.Where(x => x.AcademicYear == academicYear);
        }

        if (!string.IsNullOrWhiteSpace(className))
        {
            query = query.Where(x => x.ClassName == className);
        }

        var events = await query
            .OrderByDescending(x => x.Date)
            .ToListAsync(cancellationToken);

        return Ok(events);
    }

    [HttpPost("attendance/bulk")]
    public async Task<IActionResult> BulkUpsertAttendance([FromBody] BulkUpdateAttendanceRequest request, CancellationToken cancellationToken)
    {
        if (request.Events == null || request.Events.Count == 0)
        {
            return BadRequest(new { error = "Aucun événement d'assiduité fourni." });
        }

        var countCreated = 0;
        var countUpdated = 0;

        foreach (var req in request.Events)
        {
            var existing = await dbContext.AttendanceEvents
                .FirstOrDefaultAsync(x => 
                    x.StudentId == req.StudentId && 
                    x.Date == req.Date && 
                    x.Type == req.Type, 
                cancellationToken);

            if (existing != null)
            {
                existing.Minutes = req.Minutes;
                existing.Justified = req.Justified;
                existing.Reason = req.Reason;
                existing.AcademicYear = req.AcademicYear;
                existing.ClassName = req.ClassName;
                existing.RecordedBy = req.RecordedBy;
                countUpdated++;
            }
            else
            {
                var ev = new AttendanceEvent
                {
                    StudentId = req.StudentId,
                    AcademicYear = req.AcademicYear,
                    ClassName = req.ClassName,
                    Date = req.Date,
                    Type = req.Type,
                    Minutes = req.Minutes,
                    Justified = req.Justified,
                    Reason = req.Reason,
                    RecordedBy = req.RecordedBy
                };
                dbContext.AttendanceEvents.Add(ev);
                countCreated++;
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        return Ok(new { created = countCreated, updated = countUpdated });
    }

    [HttpGet("sanctions")]
    public async Task<IActionResult> ListSanctions(
        [FromQuery] string? studentId,
        [FromQuery] string? academicYear,
        [FromQuery] string? className,
        CancellationToken cancellationToken)
    {
        var query = dbContext.SanctionEvents.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(studentId))
        {
            query = query.Where(x => x.StudentId == studentId);
        }

        if (!string.IsNullOrWhiteSpace(academicYear))
        {
            query = query.Where(x => x.AcademicYear == academicYear);
        }

        if (!string.IsNullOrWhiteSpace(className))
        {
            query = query.Where(x => x.ClassName == className);
        }

        var sanctions = await query
            .OrderByDescending(x => x.Date)
            .ToListAsync(cancellationToken);

        return Ok(sanctions);
    }

    [HttpPost("sanctions/bulk")]
    public async Task<IActionResult> BulkUpsertSanctions([FromBody] BulkUpdateSanctionsRequest request, CancellationToken cancellationToken)
    {
        if (request.Events == null || request.Events.Count == 0)
        {
            return BadRequest(new { error = "Aucune sanction fournie." });
        }

        var countCreated = 0;
        var countUpdated = 0;

        foreach (var req in request.Events)
        {
            var existing = await dbContext.SanctionEvents
                .FirstOrDefaultAsync(x => 
                    x.StudentId == req.StudentId && 
                    x.Date == req.Date && 
                    x.Type == req.Type, 
                cancellationToken);

            if (existing != null)
            {
                existing.Description = req.Description;
                existing.AcademicYear = req.AcademicYear;
                existing.ClassName = req.ClassName;
                existing.RecordedBy = req.RecordedBy;
                countUpdated++;
            }
            else
            {
                var ev = new SanctionEvent
                {
                    StudentId = req.StudentId,
                    AcademicYear = req.AcademicYear,
                    ClassName = req.ClassName,
                    Date = req.Date,
                    Type = req.Type,
                    Description = req.Description,
                    RecordedBy = req.RecordedBy
                };
                dbContext.SanctionEvents.Add(ev);
                countCreated++;
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        return Ok(new { created = countCreated, updated = countUpdated });
    }

    [HttpDelete("attendance/{id}")]
    public async Task<IActionResult> DeleteAttendance(Guid id, CancellationToken cancellationToken)
    {
        var ev = await dbContext.AttendanceEvents.FindAsync(new object[] { id }, cancellationToken);
        if (ev == null) return NotFound();
        dbContext.AttendanceEvents.Remove(ev);
        await dbContext.SaveChangesAsync(cancellationToken);
        return NoContent();
    }

    [HttpDelete("sanctions/{id}")]
    public async Task<IActionResult> DeleteSanction(Guid id, CancellationToken cancellationToken)
    {
        var ev = await dbContext.SanctionEvents.FindAsync(new object[] { id }, cancellationToken);
        if (ev == null) return NotFound();
        dbContext.SanctionEvents.Remove(ev);
        await dbContext.SaveChangesAsync(cancellationToken);
        return NoContent();
    }
}

public class BulkUpdateAttendanceRequest
{
    public List<AttendanceEventDto> Events { get; set; } = new();
}

public class AttendanceEventDto
{
    public string StudentId { get; set; } = string.Empty;
    public string AcademicYear { get; set; } = string.Empty;
    public string ClassName { get; set; } = string.Empty;
    public string Date { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public int Minutes { get; set; }
    public bool Justified { get; set; }
    public string? Reason { get; set; }
    public string? RecordedBy { get; set; }
}

public class BulkUpdateSanctionsRequest
{
    public List<SanctionEventDto> Events { get; set; } = new();
}

public class SanctionEventDto
{
    public string StudentId { get; set; } = string.Empty;
    public string AcademicYear { get; set; } = string.Empty;
    public string ClassName { get; set; } = string.Empty;
    public string Date { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string? RecordedBy { get; set; }
}
