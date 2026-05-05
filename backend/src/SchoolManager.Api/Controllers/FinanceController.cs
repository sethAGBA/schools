using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Auditing;
using SchoolManager.Api.Data;
using SchoolManager.Modules.Finance;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/finance")]
[Authorize(Policy = "StaffOrAdmin")]
public sealed class FinanceController(SchoolDbContext dbContext, IAuditLogger auditLogger) : ControllerBase
{
    [HttpGet("payments")]
    public async Task<IActionResult> ListPayments(
        [FromQuery] Guid? studentId,
        [FromQuery] string? className,
        [FromQuery] string? academicYear,
        CancellationToken cancellationToken)
    {
        var query = dbContext.Payments.AsNoTracking();

        if (studentId.HasValue)
        {
            query = query.Where(x => x.StudentId == studentId.Value);
        }

        if (!string.IsNullOrWhiteSpace(className))
        {
            query = query.Where(x => x.ClassName == className.Trim());
        }

        if (!string.IsNullOrWhiteSpace(academicYear))
        {
            query = query.Where(x => x.ClassAcademicYear == academicYear.Trim());
        }

        var payments = await query
            .OrderByDescending(x => x.Date)
            .ToListAsync(cancellationToken);

        return Ok(payments);
    }

    [HttpPost("payments/bulk")]
    public async Task<IActionResult> BulkUpsertPayments([FromBody] BulkUpdatePaymentsRequest request, CancellationToken cancellationToken)
    {
        if (request.Payments == null || request.Payments.Count == 0)
        {
            return BadRequest(new { error = "Aucun paiement fourni." });
        }

        // Pour éviter les doublons accidentels lors de la synchronisation depuis Flutter,
        // nous pouvons faire correspondre les paiements par StudentId, Amount, et Date (et ReceiptNo si dispo).
        // Cependant, comme Flutter génère parfois plusieurs petits paiements le même jour,
        // c'est plus sûr d'insérer les paiements si on ne peut pas les identifier formellement, 
        // ou de les mettre à jour via un ID ou ReceiptNo unique.
        
        var countCreated = 0;
        var countUpdated = 0;

        foreach (var req in request.Payments)
        {
            // Vérification si un paiement identique existe déjà.
            // On se base sur StudentId, Montant, Date et Numéro de reçu.
            var existingQuery = dbContext.Payments.Where(x => 
                x.StudentId == req.StudentId && 
                x.Amount == req.Amount && 
                x.Date == req.Date);

            if (!string.IsNullOrWhiteSpace(req.ReceiptNo))
            {
                existingQuery = existingQuery.Where(x => x.ReceiptNo == req.ReceiptNo);
            }

            var existing = await existingQuery.FirstOrDefaultAsync(cancellationToken);

            if (existing != null)
            {
                existing.ClassName = req.ClassName;
                existing.ClassAcademicYear = req.ClassAcademicYear;
                existing.Comment = req.Comment;
                existing.IsCancelled = req.IsCancelled;
                existing.CancelledAt = req.CancelledAt;
                existing.CancelReason = req.CancelReason;
                existing.CancelBy = req.CancelBy;
                existing.RecordedBy = req.RecordedBy;
                
                countUpdated++;
            }
            else
            {
                var payment = new Payment
                {
                    StudentId = req.StudentId,
                    ClassName = req.ClassName,
                    ClassAcademicYear = req.ClassAcademicYear,
                    ReceiptNo = req.ReceiptNo,
                    Amount = req.Amount,
                    Date = req.Date,
                    Comment = req.Comment,
                    IsCancelled = req.IsCancelled,
                    CancelledAt = req.CancelledAt,
                    CancelReason = req.CancelReason,
                    CancelBy = req.CancelBy,
                    RecordedBy = req.RecordedBy
                };
                dbContext.Payments.Add(payment);
                countCreated++;
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);

        await auditLogger.LogAsync(
            action: "finance.payments_bulk_upsert",
            targetType: "Payment",
            targetId: "multiple",
            targetTenantId: "context",
            metadata: new { countCreated, countUpdated },
            cancellationToken);

        return Ok(new { message = "Paiements traités avec succès.", created = countCreated, updated = countUpdated });
    }

    [HttpDelete("payments/{id}")]
    public async Task<IActionResult> DeletePayment(Guid id, CancellationToken cancellationToken)
    {
        var payment = await dbContext.Payments.FindAsync(new object[] { id }, cancellationToken);
        if (payment == null)
        {
            return NotFound(new { error = "Paiement non trouvé." });
        }

        dbContext.Payments.Remove(payment);
        await dbContext.SaveChangesAsync(cancellationToken);

        await auditLogger.LogAsync(
            action: "finance.payment_delete",
            targetType: "Payment",
            targetId: id.ToString(),
            targetTenantId: "context",
            metadata: new { payment.Amount, payment.StudentId },
            cancellationToken);

        return NoContent();
    }
}

public class BulkUpdatePaymentsRequest
{
    public List<PaymentDto> Payments { get; set; } = new();
}

public class PaymentDto
{
    public Guid StudentId { get; set; }
    public string ClassName { get; set; } = string.Empty;
    public string ClassAcademicYear { get; set; } = string.Empty;
    public string? ReceiptNo { get; set; }
    public double Amount { get; set; }
    public string Date { get; set; } = string.Empty;
    public string? Comment { get; set; }
    public bool IsCancelled { get; set; }
    public string? CancelledAt { get; set; }
    public string? CancelReason { get; set; }
    public string? CancelBy { get; set; }
    public string? RecordedBy { get; set; }
}
