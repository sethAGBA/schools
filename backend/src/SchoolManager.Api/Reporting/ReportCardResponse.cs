namespace SchoolManager.Api.Reporting;

public sealed record ClassRoomInfo(Guid Id, string Name, string AcademicYear, string? Level);

public sealed record GradeEntry(
    Guid SubjectId,
    string SubjectName,
    double Coefficient,
    Guid? CategoryId,
    double? DevoirNote,
    double? CompositionNote,
    double? Average,
    string? TeacherComment,
    double? ClassAverage);

public sealed record StudentReportCard(
    Guid Id,
    string FirstName,
    string LastName,
    DateTime DateOfBirth,
    string Gender,
    double? GeneralAverage,
    int? Rank,
    IReadOnlyList<GradeEntry> Grades);

public sealed record ReportCardResponse(
    ClassRoomInfo ClassRoom,
    string Period,
    IReadOnlyList<StudentReportCard> Students);
