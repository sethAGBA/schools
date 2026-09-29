using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Data;
using SchoolManager.Api.Reporting;
using SchoolManager.Modules.Academics;

namespace SchoolManager.Api.Controllers;

[ApiController]
[Route("api/reporting")]
[Authorize(Policy = "StaffOrAdmin")]
public sealed class ReportingController(SchoolDbContext dbContext) : ControllerBase
{
    [HttpGet("report-card")]
    public async Task<IActionResult> GetReportCard(
        [FromQuery] Guid classId,
        [FromQuery] string academicYear,
        [FromQuery] string period,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(academicYear))
        {
            return BadRequest(new { error = "L'année académique est obligatoire." });
        }

        if (string.IsNullOrWhiteSpace(period))
        {
            return BadRequest(new { error = "La période est obligatoire." });
        }

        // 1. Verify the class exists (global query filter handles tenant scoping)
        var classRoom = await dbContext.Classes
            .AsNoTracking()
            .SingleOrDefaultAsync(x => x.Id == classId, cancellationToken);

        if (classRoom is null)
        {
            return NotFound(new { error = "Classe introuvable." });
        }

        // 2. Load active students for this class and academic year
        var students = await dbContext.Students
            .AsNoTracking()
            .Where(x => x.IsActive && x.ClassName == classRoom.Name && x.AcademicYear == academicYear.Trim())
            .OrderBy(x => x.LastName)
            .ThenBy(x => x.FirstName)
            .ToListAsync(cancellationToken);

        if (students.Count == 0)
        {
            return Ok(new ReportCardResponse(
                ClassRoom: new ClassRoomInfo(classRoom.Id, classRoom.Name, classRoom.AcademicYear, classRoom.Level),
                Period: period.Trim(),
                Students: []));
        }

        // 3. Load subjects for this class
        var subjects = await dbContext.Subjects
            .AsNoTracking()
            .Where(x => x.ClassRoomId == classId)
            .OrderBy(x => x.Name)
            .ToListAsync(cancellationToken);

        var subjectIds = subjects.Select(x => x.Id).ToList();
        var studentIds = students.Select(x => x.Id).ToList();

        // 4. Load all grades for these students × subjects × period in one query
        var grades = await dbContext.Grades
            .AsNoTracking()
            .Where(x => studentIds.Contains(x.StudentId)
                     && subjectIds.Contains(x.SubjectId)
                     && x.Period == period.Trim())
            .ToListAsync(cancellationToken);

        // Build lookup: studentId -> (subjectId -> grade)
        var gradesByStudent = grades
            .GroupBy(g => g.StudentId)
            .ToDictionary(g => g.Key, g => g.ToDictionary(x => x.SubjectId));

        // 5. Calculate per-student general average and build grade entries
        var studentCards = students.Select(student =>
        {
            var studentGrades = gradesByStudent.TryGetValue(student.Id, out var sg) ? sg : new Dictionary<Guid, Grade>();

            var gradeEntries = subjects.Select(subject =>
            {
                studentGrades.TryGetValue(subject.Id, out var grade);
                return new GradeEntry(
                    SubjectId: subject.Id,
                    SubjectName: subject.Name,
                    Coefficient: subject.Coefficient,
                    CategoryId: subject.CategoryId,
                    DevoirNote: grade?.DevoirNote,
                    CompositionNote: grade?.CompositionNote,
                    Average: grade?.Average,
                    TeacherComment: grade?.TeacherComment,
                    ClassAverage: grade?.ClassAverage);
            }).ToList();

            // Weighted average: Σ(average * coefficient) / Σ(coefficient of subjects that have a note)
            var subjectsWithGrade = subjects
                .Where(s => studentGrades.TryGetValue(s.Id, out var g) && g.Average.HasValue)
                .ToList();

            double? generalAverage = null;
            if (subjectsWithGrade.Count > 0)
            {
                var weightedSum = subjectsWithGrade.Sum(s => studentGrades[s.Id].Average!.Value * s.Coefficient);
                var totalCoefficient = subjectsWithGrade.Sum(s => s.Coefficient);
                generalAverage = totalCoefficient > 0 ? weightedSum / totalCoefficient : null;
            }

            return (Student: student, GeneralAverage: generalAverage, GradeEntries: (IReadOnlyList<GradeEntry>)gradeEntries);
        }).ToList();

        // 6. Calculate dense ranks (descending by average; null averages get null rank)
        // Dense rank: 1, 2, 2, 4 — ties share the same rank, next rank skips by count of tied
        var ranked = studentCards
            .Where(x => x.GeneralAverage.HasValue)
            .OrderByDescending(x => x.GeneralAverage!.Value)
            .ToList();

        var rankMap = new Dictionary<int, int>(); // index in studentCards -> rank
        var studentCardsIndexed = studentCards
            .Select((x, i) => (x, i))
            .ToList();

        int currentRank = 1;
        for (int i = 0; i < ranked.Count; )
        {
            var currentAvg = ranked[i].GeneralAverage!.Value;
            // Find all students with the same average
            int j = i;
            while (j < ranked.Count && ranked[j].GeneralAverage!.Value == currentAvg)
            {
                j++;
            }
            // i..j-1 all share currentRank
            int tieCount = j - i;
            // Store rank for each of these students by finding them in studentCards
            for (int k = i; k < j; k++)
            {
                var tiedStudent = ranked[k].Student;
                var idx = studentCardsIndexed.First(x => x.x.Student.Id == tiedStudent.Id).i;
                rankMap[idx] = currentRank;
            }
            currentRank += tieCount;
            i = j;
        }

        // 7. Build final response
        var studentReportCards = studentCardsIndexed.Select(tuple =>
        {
            var (item, idx) = tuple;
            int? rank = rankMap.TryGetValue(idx, out var r) ? r : null;
            return new StudentReportCard(
                Id: item.Student.Id,
                FirstName: item.Student.FirstName,
                LastName: item.Student.LastName,
                DateOfBirth: item.Student.DateOfBirth,
                Gender: item.Student.Gender,
                GeneralAverage: item.GeneralAverage,
                Rank: rank,
                Grades: item.GradeEntries);
        }).ToList();

        return Ok(new ReportCardResponse(
            ClassRoom: new ClassRoomInfo(classRoom.Id, classRoom.Name, classRoom.AcademicYear, classRoom.Level),
            Period: period.Trim(),
            Students: studentReportCards));
    }

    [HttpGet("class-summary")]
    public async Task<IActionResult> GetClassSummary(
        [FromQuery] string academicYear,
        [FromQuery] string period,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(academicYear))
        {
            return BadRequest(new { error = "L'année académique est obligatoire." });
        }

        if (string.IsNullOrWhiteSpace(period))
        {
            return BadRequest(new { error = "La période est obligatoire." });
        }

        var trimmedYear = academicYear.Trim();
        var trimmedPeriod = period.Trim();

        // 1. Load all classes for this tenant and academic year
        var classes = await dbContext.Classes
            .AsNoTracking()
            .Where(x => x.AcademicYear == trimmedYear)
            .OrderBy(x => x.Name)
            .ToListAsync(cancellationToken);

        if (classes.Count == 0)
        {
            return Ok(Array.Empty<ClassSummaryResponse>());
        }

        var classNames = classes.Select(x => x.Name).ToList();
        var classIds = classes.Select(x => x.Id).ToList();

        // 2. Load all active students for these classes in one query
        var allStudents = await dbContext.Students
            .AsNoTracking()
            .Where(x => x.IsActive && classNames.Contains(x.ClassName) && x.AcademicYear == trimmedYear)
            .Select(x => new { x.Id, x.ClassName })
            .ToListAsync(cancellationToken);

        // 3. Load all subjects for these classes in one query
        var allSubjects = await dbContext.Subjects
            .AsNoTracking()
            .Where(x => classIds.Contains(x.ClassRoomId))
            .Select(x => new { x.Id, x.ClassRoomId, x.Coefficient })
            .ToListAsync(cancellationToken);

        var allStudentIds = allStudents.Select(x => x.Id).ToList();
        var allSubjectIds = allSubjects.Select(x => x.Id).ToList();

        // 4. Load all grades for these students × subjects × period in one query
        var allGrades = await dbContext.Grades
            .AsNoTracking()
            .Where(x => allStudentIds.Contains(x.StudentId)
                     && allSubjectIds.Contains(x.SubjectId)
                     && x.Period == trimmedPeriod
                     && x.Average.HasValue)
            .Select(x => new { x.StudentId, x.SubjectId, x.Average })
            .ToListAsync(cancellationToken);

        // Build lookups for in-memory grouping
        var studentsByClassName = allStudents
            .GroupBy(x => x.ClassName)
            .ToDictionary(g => g.Key, g => g.Select(x => x.Id).ToList());

        var subjectsByClassId = allSubjects
            .GroupBy(x => x.ClassRoomId)
            .ToDictionary(g => g.Key, g => g.ToList());

        // grade lookup: studentId -> subjectId -> average
        var gradesByStudent = allGrades
            .GroupBy(x => x.StudentId)
            .ToDictionary(g => g.Key, g => g.ToDictionary(x => x.SubjectId, x => x.Average!.Value));

        // 5. Calculate per-class summary
        var summaries = classes.Select(cls =>
        {
            var studentIds = studentsByClassName.TryGetValue(cls.Name, out var sids) ? sids : [];
            var subjects = subjectsByClassId.TryGetValue(cls.Id, out var subs) ? subs : [];
            int studentCount = studentIds.Count;

            // Compute general average per student using weighted formula
            var generalAverages = studentIds
                .Select(studentId =>
                {
                    var studentGrades = gradesByStudent.TryGetValue(studentId, out var sg) ? sg : [];
                    var subjectsWithGrade = subjects.Where(s => studentGrades.ContainsKey(s.Id)).ToList();
                    if (subjectsWithGrade.Count == 0) return (double?)null;
                    var totalCoefficient = subjectsWithGrade.Sum(s => s.Coefficient);
                    if (totalCoefficient <= 0) return (double?)null;
                    var weightedSum = subjectsWithGrade.Sum(s => studentGrades[s.Id] * s.Coefficient);
                    return (double?)(weightedSum / totalCoefficient);
                })
                .ToList();

            var nonNullAverages = generalAverages.Where(a => a.HasValue).Select(a => a!.Value).ToList();

            double? classAverage = nonNullAverages.Count > 0
                ? nonNullAverages.Average()
                : null;

            double passRate = studentCount == 0
                ? 0.0
                : (double)nonNullAverages.Count(a => a >= 10.0) / studentCount;

            return new ClassSummaryResponse(
                ClassId: cls.Id,
                ClassName: cls.Name,
                StudentCount: studentCount,
                ClassAverage: classAverage,
                PassRate: passRate);
        }).ToList();

        return Ok(summaries);
    }
}
