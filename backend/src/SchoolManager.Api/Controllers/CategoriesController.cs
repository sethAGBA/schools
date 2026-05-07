using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Modules.Academics;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/categories")]
[Authorize(Policy = "AdminOnly")]
public sealed class CategoriesController(SchoolDbContext dbContext, IAuditLogger auditLogger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> ListCategories(CancellationToken cancellationToken)
    {
        var categories = await dbContext.SubjectCategories
            .AsNoTracking()
            .OrderBy(x => x.Order)
            .ThenBy(x => x.Name)
            .ToListAsync(cancellationToken);

        return Ok(categories);
    }

    [HttpPost]
    public async Task<IActionResult> CreateCategory(
        [FromBody] CategoryRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
        {
            return BadRequest(new { error = "Le nom de la catégorie est requis." });
        }

        var exists = await dbContext.SubjectCategories
            .AnyAsync(x => x.Name.ToLower() == request.Name.Trim().ToLower(), cancellationToken);

        if (exists)
        {
            return Conflict(new { error = "Une catégorie avec ce nom existe déjà." });
        }

        var category = new SubjectCategory
        {
            Name = request.Name.Trim(),
            Description = request.Description?.Trim(),
            Color = string.IsNullOrWhiteSpace(request.Color) ? "#6366F1" : request.Color.Trim(),
            Order = request.Order
        };

        dbContext.SubjectCategories.Add(category);
        await dbContext.SaveChangesAsync(cancellationToken);

        await auditLogger.LogAsync(
            action: "categories.created",
            targetType: "SubjectCategory",
            targetId: category.Id.ToString(),
            targetTenantId: category.TenantId,
            metadata: new { category.Name },
            cancellationToken);

        return CreatedAtAction(nameof(ListCategories), null, new CategoryDto(category));
    }

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> UpdateCategory(
        Guid id,
        [FromBody] CategoryRequest request,
        CancellationToken cancellationToken)
    {
        var category = await dbContext.SubjectCategories.FindAsync([id], cancellationToken);
        if (category is null) return NotFound(new { error = "Catégorie introuvable." });

        if (string.IsNullOrWhiteSpace(request.Name))
        {
            return BadRequest(new { error = "Le nom de la catégorie est requis." });
        }

        // Check name uniqueness (exclude self)
        var nameConflict = await dbContext.SubjectCategories
            .AnyAsync(x => x.Name.ToLower() == request.Name.Trim().ToLower() && x.Id != id, cancellationToken);

        if (nameConflict)
        {
            return Conflict(new { error = "Une autre catégorie avec ce nom existe déjà." });
        }

        category.Name = request.Name.Trim();
        category.Description = request.Description?.Trim();
        category.Color = string.IsNullOrWhiteSpace(request.Color) ? "#6366F1" : request.Color.Trim();
        category.Order = request.Order;

        await dbContext.SaveChangesAsync(cancellationToken);

        await auditLogger.LogAsync(
            action: "categories.updated",
            targetType: "SubjectCategory",
            targetId: category.Id.ToString(),
            targetTenantId: category.TenantId,
            metadata: new { category.Name },
            cancellationToken);

        return Ok(new CategoryDto(category));
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> DeleteCategory(Guid id, CancellationToken cancellationToken)
    {
        var category = await dbContext.SubjectCategories.FindAsync([id], cancellationToken);
        if (category is null) return NotFound(new { error = "Catégorie introuvable." });

        dbContext.SubjectCategories.Remove(category);
        await dbContext.SaveChangesAsync(cancellationToken);

        await auditLogger.LogAsync(
            action: "categories.deleted",
            targetType: "SubjectCategory",
            targetId: id.ToString(),
            targetTenantId: category.TenantId,
            metadata: new { category.Name },
            cancellationToken);

        return NoContent();
    }
}

public sealed record CategoryRequest(
    string Name,
    string? Description,
    string? Color,
    int Order);

public sealed record CategoryDto(
    Guid Id,
    string Name,
    string? Description,
    string Color,
    int Order)
{
    public CategoryDto(SubjectCategory c) : this(c.Id, c.Name, c.Description, c.Color, c.Order) { }
}
