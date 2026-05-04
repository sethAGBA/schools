using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Academics;

public record UpsertGradeRequest(
    [Required] Guid StudentId,
    [Required] Guid SubjectId,
    [Required] string Period,
    double? DevoirNote,
    double? CompositionNote,
    double? Average,
    string? TeacherComment,
    double? ClassAverage);

public record BulkUpdateGradesRequest(
    [Required] List<UpsertGradeRequest> Grades);
