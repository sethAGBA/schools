using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Modules.Academics;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/timetable")]
[Authorize(Policy = "StaffOrAdmin")]
public sealed class TimetableController(SchoolDbContext dbContext, IAuditLogger auditLogger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> ListEntries(
        [FromQuery] string? className,
        [FromQuery] string? academicYear,
        CancellationToken cancellationToken)
    {
        var query = dbContext.TimetableEntries.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(className))
        {
            query = query.Where(x => x.ClassName == className);
        }

        if (!string.IsNullOrWhiteSpace(academicYear))
        {
            query = query.Where(x => x.AcademicYear == academicYear);
        }

        var entries = await query
            .OrderBy(x => x.DayOfWeek)
            .ThenBy(x => x.StartTime)
            .ToListAsync(cancellationToken);

        return Ok(entries);
    }

    [HttpPost("bulk")]
    public async Task<IActionResult> BulkUpsert([FromBody] BulkTimetableRequest request, CancellationToken cancellationToken)
    {
        if (request.Entries == null || request.Entries.Count == 0)
        {
            return BadRequest("No entries provided.");
        }

        foreach (var dto in request.Entries)
        {
            var existing = await dbContext.TimetableEntries
                .FirstOrDefaultAsync(x => x.Id == dto.Id, cancellationToken);

            if (existing != null)
            {
                existing.Subject = dto.Subject;
                existing.Teacher = dto.Teacher;
                existing.ClassName = dto.ClassName;
                existing.AcademicYear = dto.AcademicYear;
                existing.DayOfWeek = dto.DayOfWeek;
                existing.StartTime = dto.StartTime;
                existing.EndTime = dto.EndTime;
                existing.Room = dto.Room;
                existing.UpdatedAtUtc = DateTimeOffset.UtcNow;
            }
            else
            {
                dbContext.TimetableEntries.Add(new TimetableEntry
                {
                    Id = dto.Id ?? Guid.NewGuid(),
                    Subject = dto.Subject,
                    Teacher = dto.Teacher,
                    ClassName = dto.ClassName,
                    AcademicYear = dto.AcademicYear,
                    DayOfWeek = dto.DayOfWeek,
                    StartTime = dto.StartTime,
                    EndTime = dto.EndTime,
                    Room = dto.Room
                });
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        await auditLogger.LogAsync(
            action: "academics.timetable_bulk_upsert",
            targetType: "Timetable",
            targetId: "multiple",
            targetTenantId: null, // Managed by TenantInterceptor
            metadata: new { Count = request.Entries.Count },
            cancellationToken: cancellationToken);

        return Ok();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> DeleteEntry(Guid id, CancellationToken cancellationToken)
    {
        var entry = await dbContext.TimetableEntries.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
        if (entry == null) return NotFound();

        dbContext.TimetableEntries.Remove(entry);
        await dbContext.SaveChangesAsync(cancellationToken);
        await auditLogger.LogAsync(
            action: "academics.timetable_deleted",
            targetType: "Timetable",
            targetId: id.ToString(),
            targetTenantId: entry.TenantId,
            metadata: new { entry.Subject, entry.ClassName },
            cancellationToken: cancellationToken);

        return NoContent();
    }
}

public class BulkTimetableRequest
{
    public List<TimetableEntryDto> Entries { get; set; } = [];
}

public class TimetableEntryDto
{
    public Guid? Id { get; set; }
    public string Subject { get; set; } = string.Empty;
    public string Teacher { get; set; } = string.Empty;
    public string ClassName { get; set; } = string.Empty;
    public string AcademicYear { get; set; } = string.Empty;
    public string DayOfWeek { get; set; } = string.Empty;
    public string StartTime { get; set; } = string.Empty;
    public string EndTime { get; set; } = string.Empty;
    public string? Room { get; set; }
}
