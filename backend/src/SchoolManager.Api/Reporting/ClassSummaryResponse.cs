namespace SchoolManager.Api.Reporting;

public sealed record ClassSummaryResponse(
    Guid ClassId,
    string ClassName,
    int StudentCount,
    double? ClassAverage,
    double PassRate);
