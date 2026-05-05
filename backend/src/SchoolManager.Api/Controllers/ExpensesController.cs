using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Modules.Finance;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/finance/expenses")]
[Authorize(Policy = "StaffOrAdmin")]
public sealed class ExpensesController(SchoolDbContext dbContext, IAuditLogger auditLogger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> ListExpenses(
        [FromQuery] string? category,
        [FromQuery] string? academicYear,
        CancellationToken cancellationToken)
    {
        var query = dbContext.Expenses.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(category))
        {
            query = query.Where(x => x.Category == category.Trim());
        }

        if (!string.IsNullOrWhiteSpace(academicYear))
        {
            query = query.Where(x => x.AcademicYear == academicYear.Trim());
        }

        var expenses = await query
            .OrderByDescending(x => x.Date)
            .ToListAsync(cancellationToken);

        return Ok(expenses);
    }

    [HttpPost("bulk")]
    public async Task<IActionResult> BulkUpsertExpenses([FromBody] BulkUpdateExpensesRequest request, CancellationToken cancellationToken)
    {
        if (request.Expenses == null || request.Expenses.Count == 0)
        {
            return BadRequest(new { error = "Aucune dépense fournie." });
        }

        var countCreated = 0;
        var countUpdated = 0;

        foreach (var req in request.Expenses)
        {
            // Match based on Label, Amount, Date, and AcademicYear
            var existing = await dbContext.Expenses
                .FirstOrDefaultAsync(x => 
                    x.Label == req.Label && 
                    x.Amount == req.Amount && 
                    x.Date == req.Date &&
                    x.AcademicYear == req.AcademicYear, 
                cancellationToken);

            if (existing != null)
            {
                existing.Category = req.Category;
                existing.SupplierId = req.SupplierId;
                existing.Supplier = req.Supplier;
                existing.ClassName = req.ClassName;
                
                countUpdated++;
            }
            else
            {
                var expense = new Expense
                {
                    Label = req.Label,
                    Category = req.Category,
                    SupplierId = req.SupplierId,
                    Supplier = req.Supplier,
                    Amount = req.Amount,
                    Date = req.Date,
                    ClassName = req.ClassName,
                    AcademicYear = req.AcademicYear
                };
                dbContext.Expenses.Add(expense);
                countCreated++;
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);

        await auditLogger.LogAsync(
            action: "finance.expenses_bulk_upsert",
            targetType: "Expense",
            targetId: "multiple",
            targetTenantId: "context",
            metadata: new { countCreated, countUpdated },
            cancellationToken);

        return Ok(new { message = "Dépenses traitées avec succès.", created = countCreated, updated = countUpdated });
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> DeleteExpense(Guid id, CancellationToken cancellationToken)
    {
        var expense = await dbContext.Expenses.FindAsync(new object[] { id }, cancellationToken);
        if (expense == null)
        {
            return NotFound(new { error = "Dépense non trouvée." });
        }

        dbContext.Expenses.Remove(expense);
        await dbContext.SaveChangesAsync(cancellationToken);

        await auditLogger.LogAsync(
            action: "finance.expense_delete",
            targetType: "Expense",
            targetId: id.ToString(),
            targetTenantId: "context",
            metadata: new { expense.Label, expense.Amount },
            cancellationToken);

        return NoContent();
    }
}

public class BulkUpdateExpensesRequest
{
    public List<ExpenseDto> Expenses { get; set; } = new();
}

public class ExpenseDto
{
    public string Label { get; set; } = string.Empty;
    public string? Category { get; set; }
    public int? SupplierId { get; set; }
    public string? Supplier { get; set; }
    public double Amount { get; set; }
    public string Date { get; set; } = string.Empty;
    public string? ClassName { get; set; }
    public string AcademicYear { get; set; } = string.Empty;
}
