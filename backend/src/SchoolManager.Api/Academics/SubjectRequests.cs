using System.ComponentModel.DataAnnotations;

namespace SchoolManager.Api.Academics;

public record CreateSubjectRequest(
    [Required] string Name,
    [Range(0.1, 50)] double Coefficient,
    [Required] Guid ClassRoomId);

public record UpdateSubjectRequest(
    [Required] string Name,
    [Range(0.1, 50)] double Coefficient);
