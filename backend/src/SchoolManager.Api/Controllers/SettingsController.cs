using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Modules.Academics;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/settings")]
[Authorize(Policy = "AdminOnly")]
public sealed class SettingsController(SchoolDbContext dbContext, IAuditLogger auditLogger) : ControllerBase
{
    /// <summary>Retourne tous les paramètres de l'établissement pour ce tenant.</summary>
    [HttpGet]
    public async Task<IActionResult> GetSettings(CancellationToken cancellationToken)
    {
        var rows = await dbContext.SchoolSettings
            .AsNoTracking()
            .OrderBy(x => x.Key)
            .ToListAsync(cancellationToken);

        var dict = rows.ToDictionary(r => r.Key, r => r.Value);
        return Ok(dict);
    }

    /// <summary>Upsert en batch les paramètres de l'établissement.</summary>
    [HttpPut]
    public async Task<IActionResult> UpsertSettings(
        [FromBody] Dictionary<string, string> settings,
        CancellationToken cancellationToken)
    {
        if (settings == null || settings.Count == 0)
        {
            return BadRequest(new { error = "Aucun paramètre fourni." });
        }

        var keys = settings.Keys.ToList();
        var existing = await dbContext.SchoolSettings
            .Where(x => keys.Contains(x.Key))
            .ToListAsync(cancellationToken);

        foreach (var (key, value) in settings)
        {
            var row = existing.FirstOrDefault(x => x.Key == key);
            if (row is not null)
            {
                row.Value = value ?? string.Empty;
            }
            else
            {
                dbContext.SchoolSettings.Add(new SchoolSettings
                {
                    Key = key,
                    Value = value ?? string.Empty
                });
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);

        await auditLogger.LogAsync(
            action: "settings.upserted",
            targetType: "SchoolSettings",
            targetId: "batch",
            targetTenantId: null,
            metadata: new { count = settings.Count },
            cancellationToken);

        return Ok(new { message = "Paramètres sauvegardés.", count = settings.Count });
    }
}
