using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Academics;

public record CreateClassRequest(
    [Required] string Name,
    [Required] string AcademicYear,
    string? Level,
    [Range(1, 500)] int Capacity);

public record UpdateClassRequest(
    [Required] string Name,
    [Required] string AcademicYear,
    string? Level,
    [Range(1, 500)] int Capacity);
