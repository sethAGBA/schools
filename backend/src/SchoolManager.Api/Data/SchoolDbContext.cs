using Microsoft.EntityFrameworkCore;
using SchoolManager.Api.Multitenancy;
using SchoolManager.Modules.Audit;
using SchoolManager.Modules.Identity.Domain;
using SchoolManager.Modules.Students;
using SchoolManager.Modules.Academics;
using SchoolManager.Modules.Tenancy;
using SchoolManager.Modules.Finance;
using SchoolManager.Modules.Staff;

namespace SchoolManager.Api.Data;

public sealed class SchoolDbContext(DbContextOptions<SchoolDbContext> options, ITenantContext tenantContext)
    : DbContext(options)
{
    private readonly ITenantContext _tenantContext = tenantContext;

    public DbSet<AppUser> Users => Set<AppUser>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<Tenant> Tenants => Set<Tenant>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<LoginAttempt> LoginAttempts => Set<LoginAttempt>();
    public DbSet<StudentRecord> Students => Set<StudentRecord>();
    public DbSet<ClassRoom> Classes => Set<ClassRoom>();
    public DbSet<Subject> Subjects => Set<Subject>();
    public DbSet<Grade> Grades => Set<Grade>();
    public DbSet<Payment> Payments => Set<Payment>();
    public DbSet<Expense> Expenses => Set<Expense>();
    public DbSet<AttendanceEvent> AttendanceEvents => Set<AttendanceEvent>();
    public DbSet<SanctionEvent> SanctionEvents => Set<SanctionEvent>();
    public DbSet<StaffMember> StaffMembers => Set<StaffMember>();
    public DbSet<TimetableEntry> TimetableEntries => Set<TimetableEntry>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<AppUser>(entity =>
        {
            entity.ToTable("users");
            entity.HasKey(x => x.Id);

            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.TenantId).HasColumnName("tenant_id").HasMaxLength(100).IsRequired();
            entity.Property(x => x.Email).HasColumnName("email").HasMaxLength(320).IsRequired();
            entity.Property(x => x.PasswordHash).HasColumnName("password_hash").HasMaxLength(500).IsRequired();
            entity.Property(x => x.Role).HasColumnName("role").HasMaxLength(50).IsRequired();
            entity.Property(x => x.IsActive).HasColumnName("is_active").IsRequired();
            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc").IsRequired();

            entity.HasIndex(x => new { x.TenantId, x.Email }).IsUnique();
            entity.HasQueryFilter(x => _tenantContext.TenantId == null || x.TenantId == _tenantContext.TenantId);
        });

        modelBuilder.Entity<RefreshToken>(entity =>
        {
            entity.ToTable("refresh_tokens");
            entity.HasKey(x => x.Id);

            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.TenantId).HasColumnName("tenant_id").HasMaxLength(100).IsRequired();
            entity.Property(x => x.UserId).HasColumnName("user_id").IsRequired();
            entity.Property(x => x.TokenHash).HasColumnName("token_hash").HasMaxLength(128).IsRequired();
            entity.Property(x => x.ExpiresAtUtc).HasColumnName("expires_at_utc").IsRequired();
            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc").IsRequired();
            entity.Property(x => x.RevokedAtUtc).HasColumnName("revoked_at_utc");

            entity.HasIndex(x => x.TokenHash).IsUnique();
            entity.HasIndex(x => new { x.TenantId, x.UserId });
            entity.HasOne(x => x.User)
                .WithMany(x => x.RefreshTokens)
                .HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasQueryFilter(x => _tenantContext.TenantId == null || x.TenantId == _tenantContext.TenantId);
        });

        modelBuilder.Entity<Tenant>(entity =>
        {
            entity.ToTable("tenants");
            entity.HasKey(x => x.Id);

            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.Code).HasColumnName("code").HasMaxLength(100).IsRequired();
            entity.Property(x => x.Name).HasColumnName("name").HasMaxLength(200).IsRequired();
            entity.Property(x => x.IsActive).HasColumnName("is_active").IsRequired();
            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc").IsRequired();

            entity.HasIndex(x => x.Code).IsUnique();
        });

        modelBuilder.Entity<AuditLog>(entity =>
        {
            entity.ToTable("audit_logs");
            entity.HasKey(x => x.Id);

            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.ActorUserId).HasColumnName("actor_user_id");
            entity.Property(x => x.ActorEmail).HasColumnName("actor_email").HasMaxLength(320);
            entity.Property(x => x.ActorRole).HasColumnName("actor_role").HasMaxLength(50);
            entity.Property(x => x.Action).HasColumnName("action").HasMaxLength(120).IsRequired();
            entity.Property(x => x.TargetType).HasColumnName("target_type").HasMaxLength(120).IsRequired();
            entity.Property(x => x.TargetId).HasColumnName("target_id").HasMaxLength(120);
            entity.Property(x => x.TargetTenantId).HasColumnName("target_tenant_id").HasMaxLength(100);
            entity.Property(x => x.MetadataJson).HasColumnName("metadata_json");
            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc").IsRequired();

            entity.HasIndex(x => x.CreatedAtUtc);
            entity.HasIndex(x => new { x.TargetType, x.TargetId });
            entity.HasIndex(x => x.TargetTenantId);
        });

        modelBuilder.Entity<LoginAttempt>(entity =>
        {
            entity.ToTable("login_attempts");
            entity.HasKey(x => x.Id);

            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.TenantId).HasColumnName("tenant_id").HasMaxLength(100).IsRequired();
            entity.Property(x => x.Email).HasColumnName("email").HasMaxLength(320).IsRequired();
            entity.Property(x => x.IpAddress).HasColumnName("ip_address").HasMaxLength(64);
            entity.Property(x => x.Succeeded).HasColumnName("succeeded").IsRequired();
            entity.Property(x => x.AttemptedAtUtc).HasColumnName("attempted_at_utc").IsRequired();

            entity.HasIndex(x => new { x.TenantId, x.Email, x.IpAddress, x.AttemptedAtUtc });
            entity.HasIndex(x => x.AttemptedAtUtc);
        });

        modelBuilder.Entity<StudentRecord>(entity =>
        {
            entity.ToTable("students");
            entity.HasKey(x => x.Id);

            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.TenantId).HasColumnName("tenant_id").HasMaxLength(100).IsRequired();
            entity.Property(x => x.FirstName).HasColumnName("first_name").HasMaxLength(150).IsRequired();
            entity.Property(x => x.LastName).HasColumnName("last_name").HasMaxLength(150).IsRequired();
            entity.Property(x => x.DateOfBirth).HasColumnName("date_of_birth").IsRequired();
            entity.Property(x => x.Gender).HasColumnName("gender").HasMaxLength(30).IsRequired();
            entity.Property(x => x.ClassName).HasColumnName("class_name").HasMaxLength(120).IsRequired();
            entity.Property(x => x.AcademicYear).HasColumnName("academic_year").HasMaxLength(40).IsRequired();
            entity.Property(x => x.GuardianName).HasColumnName("guardian_name").HasMaxLength(200).IsRequired();
            entity.Property(x => x.GuardianContact).HasColumnName("guardian_contact").HasMaxLength(60).IsRequired();
            entity.Property(x => x.ContactNumber).HasColumnName("contact_number").HasMaxLength(60).IsRequired();
            entity.Property(x => x.Email).HasColumnName("email").HasMaxLength(320);
            entity.Property(x => x.Address).HasColumnName("address").HasMaxLength(500);
            entity.Property(x => x.IsActive).HasColumnName("is_active").IsRequired();
            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc").IsRequired();
            entity.Property(x => x.UpdatedAtUtc).HasColumnName("updated_at_utc").IsRequired();

            entity.HasIndex(x => new { x.TenantId, x.LastName, x.FirstName });
            entity.HasIndex(x => new { x.TenantId, x.ClassName, x.AcademicYear });
            entity.HasQueryFilter(x => _tenantContext.TenantId == null || x.TenantId == _tenantContext.TenantId);
        });

        modelBuilder.Entity<ClassRoom>(entity =>
        {
            entity.ToTable("classes");
            entity.HasKey(x => x.Id);

            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.TenantId).HasColumnName("tenant_id").HasMaxLength(100).IsRequired();
            entity.Property(x => x.Name).HasColumnName("name").HasMaxLength(150).IsRequired();
            entity.Property(x => x.AcademicYear).HasColumnName("academic_year").HasMaxLength(40).IsRequired();
            entity.Property(x => x.Level).HasColumnName("level").HasMaxLength(100);
            entity.Property(x => x.Capacity).HasColumnName("capacity").IsRequired();
            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc").IsRequired();
            entity.Property(x => x.UpdatedAtUtc).HasColumnName("updated_at_utc").IsRequired();

            entity.HasIndex(x => new { x.TenantId, x.Name, x.AcademicYear });
            entity.HasQueryFilter(x => _tenantContext.TenantId == null || x.TenantId == _tenantContext.TenantId);
        });

        modelBuilder.Entity<Subject>(entity =>
        {
            entity.ToTable("subjects");
            entity.HasKey(x => x.Id);

            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.TenantId).HasColumnName("tenant_id").HasMaxLength(100).IsRequired();
            entity.Property(x => x.Name).HasColumnName("name").HasMaxLength(150).IsRequired();
            entity.Property(x => x.Coefficient).HasColumnName("coefficient").IsRequired();
            entity.Property(x => x.ClassRoomId).HasColumnName("class_room_id").IsRequired();
            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc").IsRequired();
            entity.Property(x => x.UpdatedAtUtc).HasColumnName("updated_at_utc").IsRequired();

            entity.HasIndex(x => new { x.TenantId, x.ClassRoomId });
            entity.HasQueryFilter(x => _tenantContext.TenantId == null || x.TenantId == _tenantContext.TenantId);
        });

        modelBuilder.Entity<Grade>(entity =>
        {
            entity.ToTable("grades");
            entity.HasKey(x => x.Id);

            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.TenantId).HasColumnName("tenant_id").HasMaxLength(100).IsRequired();
            entity.Property(x => x.StudentId).HasColumnName("student_id").IsRequired();
            entity.Property(x => x.SubjectId).HasColumnName("subject_id").IsRequired();
            entity.Property(x => x.Period).HasColumnName("period").HasMaxLength(60).IsRequired();
            entity.Property(x => x.DevoirNote).HasColumnName("devoir_note");
            entity.Property(x => x.CompositionNote).HasColumnName("composition_note");
            entity.Property(x => x.Average).HasColumnName("average");
            entity.Property(x => x.TeacherComment).HasColumnName("teacher_comment").HasMaxLength(1000);
            entity.Property(x => x.ClassAverage).HasColumnName("class_average");
            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc").IsRequired();
            entity.Property(x => x.UpdatedAtUtc).HasColumnName("updated_at_utc").IsRequired();

            entity.HasIndex(x => new { x.TenantId, x.StudentId, x.Period });
            entity.HasIndex(x => new { x.TenantId, x.SubjectId, x.Period });
            entity.HasQueryFilter(x => _tenantContext.TenantId == null || x.TenantId == _tenantContext.TenantId);
        });

        modelBuilder.Entity<Payment>(entity =>
        {
            entity.ToTable("payments");
            entity.HasKey(x => x.Id);

            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.TenantId).HasColumnName("tenant_id").HasMaxLength(100).IsRequired();
            entity.Property(x => x.StudentId).HasColumnName("student_id").IsRequired();
            entity.Property(x => x.ClassName).HasColumnName("class_name").HasMaxLength(120).IsRequired();
            entity.Property(x => x.ClassAcademicYear).HasColumnName("class_academic_year").HasMaxLength(40).IsRequired();
            entity.Property(x => x.ReceiptNo).HasColumnName("receipt_no").HasMaxLength(50);
            entity.Property(x => x.Amount).HasColumnName("amount").IsRequired();
            entity.Property(x => x.Date).HasColumnName("date").HasMaxLength(30).IsRequired();
            entity.Property(x => x.Comment).HasColumnName("comment").HasMaxLength(1000);
            entity.Property(x => x.IsCancelled).HasColumnName("is_cancelled").IsRequired();
            entity.Property(x => x.CancelledAt).HasColumnName("cancelled_at").HasMaxLength(30);
            entity.Property(x => x.CancelReason).HasColumnName("cancel_reason").HasMaxLength(500);
            entity.Property(x => x.CancelBy).HasColumnName("cancel_by").HasMaxLength(100);
            entity.Property(x => x.RecordedBy).HasColumnName("recorded_by").HasMaxLength(100);
            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc").IsRequired();
            entity.Property(x => x.UpdatedAtUtc).HasColumnName("updated_at_utc").IsRequired();

            entity.HasIndex(x => new { x.TenantId, x.StudentId, x.Date });
            entity.HasIndex(x => new { x.TenantId, x.ClassName, x.ClassAcademicYear });
            entity.HasQueryFilter(x => _tenantContext.TenantId == null || x.TenantId == _tenantContext.TenantId);
        });

        modelBuilder.Entity<Expense>(entity =>
        {
            entity.ToTable("expenses");
            entity.HasKey(x => x.Id);
            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.TenantId).HasColumnName("tenant_id").IsRequired().HasMaxLength(50);
            entity.Property(x => x.Label).HasColumnName("label").IsRequired().HasMaxLength(200);
            entity.Property(x => x.Category).HasColumnName("category").HasMaxLength(100);
            entity.Property(x => x.SupplierId).HasColumnName("supplier_id");
            entity.Property(x => x.Supplier).HasColumnName("supplier").HasMaxLength(200);
            entity.Property(x => x.Amount).HasColumnName("amount").IsRequired();
            entity.Property(x => x.Date).HasColumnName("date").IsRequired().HasMaxLength(30);
            entity.Property(x => x.ClassName).HasColumnName("class_name").HasMaxLength(100);
            entity.Property(x => x.AcademicYear).HasColumnName("academic_year").IsRequired().HasMaxLength(20);
            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc").IsRequired();
            entity.Property(x => x.UpdatedAtUtc).HasColumnName("updated_at_utc").IsRequired();

            entity.HasIndex(x => new { x.TenantId, x.AcademicYear });
            entity.HasQueryFilter(x => _tenantContext.TenantId == null || x.TenantId == _tenantContext.TenantId);
        });

        modelBuilder.Entity<AttendanceEvent>(entity =>
        {
            entity.ToTable("attendance_events");
            entity.HasKey(x => x.Id);
            entity.Property(x => x.TenantId).HasMaxLength(50).IsRequired();
            entity.Property(x => x.StudentId).HasMaxLength(50).IsRequired();
            entity.Property(x => x.AcademicYear).HasMaxLength(20).IsRequired();
            entity.Property(x => x.ClassName).HasMaxLength(100).IsRequired();
            entity.Property(x => x.Date).HasMaxLength(30).IsRequired();
            entity.Property(x => x.Type).HasMaxLength(20).IsRequired();
            entity.Property(x => x.Reason).HasMaxLength(500);
            entity.Property(x => x.RecordedBy).HasMaxLength(100);

            entity.HasIndex(x => new { x.TenantId, x.AcademicYear, x.ClassName });
            entity.HasIndex(x => new { x.TenantId, x.StudentId });
            entity.HasQueryFilter(x => _tenantContext.TenantId == null || x.TenantId == _tenantContext.TenantId);
        });

        modelBuilder.Entity<SanctionEvent>(entity =>
        {
            entity.ToTable("sanction_events");
            entity.HasKey(x => x.Id);
            entity.Property(x => x.TenantId).HasMaxLength(50).IsRequired();
            entity.Property(x => x.StudentId).HasMaxLength(50).IsRequired();
            entity.Property(x => x.AcademicYear).HasMaxLength(20).IsRequired();
            entity.Property(x => x.ClassName).HasMaxLength(100).IsRequired();
            entity.Property(x => x.Date).HasMaxLength(30).IsRequired();
            entity.Property(x => x.Type).HasMaxLength(50).IsRequired();
            entity.Property(x => x.Description).HasMaxLength(1000).IsRequired();
            entity.Property(x => x.RecordedBy).HasMaxLength(100);

            entity.HasIndex(x => new { x.TenantId, x.AcademicYear, x.ClassName });
            entity.HasIndex(x => new { x.TenantId, x.StudentId });
            entity.HasQueryFilter(x => _tenantContext.TenantId == null || x.TenantId == _tenantContext.TenantId);
        });

        modelBuilder.Entity<StaffMember>(entity =>
        {
            entity.ToTable("staff");
            entity.HasKey(x => x.Id);

            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.TenantId).HasColumnName("tenant_id").HasMaxLength(100).IsRequired();
            entity.Property(x => x.Name).HasColumnName("name").HasMaxLength(255).IsRequired();
            entity.Property(x => x.Role).HasColumnName("role").HasMaxLength(100).IsRequired();
            entity.Property(x => x.Department).HasColumnName("department").HasMaxLength(100);
            entity.Property(x => x.Phone).HasColumnName("phone").HasMaxLength(50);
            entity.Property(x => x.Email).HasColumnName("email").HasMaxLength(320);
            entity.Property(x => x.Qualifications).HasColumnName("qualifications");
            entity.Property(x => x.Courses).HasColumnName("courses");
            entity.Property(x => x.Classes).HasColumnName("classes");
            entity.Property(x => x.Status).HasColumnName("status").HasMaxLength(50).IsRequired();
            entity.Property(x => x.HireDate).HasColumnName("hire_date").HasMaxLength(30).IsRequired();
            entity.Property(x => x.TypeRole).HasColumnName("type_role").HasMaxLength(50).IsRequired();

            entity.Property(x => x.FirstName).HasColumnName("first_name").HasMaxLength(150);
            entity.Property(x => x.LastName).HasColumnName("last_name").HasMaxLength(150);
            entity.Property(x => x.Gender).HasColumnName("gender").HasMaxLength(30);
            entity.Property(x => x.BirthDate).HasColumnName("birth_date").HasMaxLength(30);
            entity.Property(x => x.BirthPlace).HasColumnName("birth_place").HasMaxLength(200);
            entity.Property(x => x.Nationality).HasColumnName("nationality").HasMaxLength(100);
            entity.Property(x => x.Address).HasColumnName("address").HasMaxLength(500);
            entity.Property(x => x.PhotoPath).HasColumnName("photo_path").HasMaxLength(500);

            entity.Property(x => x.Matricule).HasColumnName("matricule").HasMaxLength(100);
            entity.Property(x => x.IdNumber).HasColumnName("id_number").HasMaxLength(100);
            entity.Property(x => x.SocialSecurityNumber).HasColumnName("social_security_number").HasMaxLength(100);
            entity.Property(x => x.MaritalStatus).HasColumnName("marital_status").HasMaxLength(50);
            entity.Property(x => x.NumberOfChildren).HasColumnName("number_of_children");

            entity.Property(x => x.Region).HasColumnName("region").HasMaxLength(100);
            entity.Property(x => x.Levels).HasColumnName("levels");
            entity.Property(x => x.HighestDegree).HasColumnName("highest_degree").HasMaxLength(200);
            entity.Property(x => x.Specialty).HasColumnName("specialty").HasMaxLength(200);
            entity.Property(x => x.ExperienceYears).HasColumnName("experience_years");
            entity.Property(x => x.PreviousInstitution).HasColumnName("previous_institution").HasMaxLength(255);

            entity.Property(x => x.ContractType).HasColumnName("contract_type").HasMaxLength(100);
            entity.Property(x => x.BaseSalary).HasColumnName("base_salary");
            entity.Property(x => x.WeeklyHours).HasColumnName("weekly_hours");
            entity.Property(x => x.Supervisor).HasColumnName("supervisor").HasMaxLength(200);
            entity.Property(x => x.RetirementDate).HasColumnName("retirement_date").HasMaxLength(30);

            entity.Property(x => x.Documents).HasColumnName("documents");

            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc").IsRequired();
            entity.Property(x => x.UpdatedAtUtc).HasColumnName("updated_at_utc").IsRequired();

            entity.HasIndex(x => new { x.TenantId, x.Name });
            entity.HasIndex(x => new { x.TenantId, x.Matricule }).IsUnique();
            entity.HasQueryFilter(x => _tenantContext.TenantId == null || x.TenantId == _tenantContext.TenantId);
        });

        modelBuilder.Entity<TimetableEntry>(entity =>
        {
            entity.ToTable("timetable_entries");
            entity.HasKey(x => x.Id);
            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.TenantId).HasColumnName("tenant_id").HasMaxLength(100).IsRequired();
            entity.Property(x => x.Subject).HasColumnName("subject").HasMaxLength(200).IsRequired();
            entity.Property(x => x.Teacher).HasColumnName("teacher").HasMaxLength(200).IsRequired();
            entity.Property(x => x.ClassName).HasColumnName("class_name").HasMaxLength(150).IsRequired();
            entity.Property(x => x.AcademicYear).HasColumnName("academic_year").HasMaxLength(40).IsRequired();
            entity.Property(x => x.DayOfWeek).HasColumnName("day_of_week").HasMaxLength(20).IsRequired();
            entity.Property(x => x.StartTime).HasColumnName("start_time").HasMaxLength(10).IsRequired();
            entity.Property(x => x.EndTime).HasColumnName("end_time").HasMaxLength(10).IsRequired();
            entity.Property(x => x.Room).HasColumnName("room").HasMaxLength(100);
            entity.Property(x => x.CreatedAtUtc).HasColumnName("created_at_utc").IsRequired();
            entity.Property(x => x.UpdatedAtUtc).HasColumnName("updated_at_utc").IsRequired();

            entity.HasIndex(x => new { x.TenantId, x.ClassName, x.AcademicYear });
            entity.HasQueryFilter(x => _tenantContext.TenantId == null || x.TenantId == _tenantContext.TenantId);
        });
    }

    public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        ApplyTenantContextForNewEntities();
        return base.SaveChangesAsync(cancellationToken);
    }

    private void ApplyTenantContextForNewEntities()
    {
        var tenantId = _tenantContext.TenantId;
        if (string.IsNullOrWhiteSpace(tenantId))
        {
            return;
        }

        foreach (var entry in ChangeTracker.Entries<AppUser>())
        {
            if (entry.State == EntityState.Added && string.IsNullOrWhiteSpace(entry.Entity.TenantId))
            {
                entry.Entity.TenantId = tenantId;
            }
        }

        foreach (var entry in ChangeTracker.Entries<RefreshToken>())
        {
            if (entry.State == EntityState.Added && string.IsNullOrWhiteSpace(entry.Entity.TenantId))
            {
                entry.Entity.TenantId = tenantId;
            }
        }

        foreach (var entry in ChangeTracker.Entries<StudentRecord>())
        {
            if (entry.State == EntityState.Added && string.IsNullOrWhiteSpace(entry.Entity.TenantId))
            {
                entry.Entity.TenantId = tenantId;
            }

            if (entry.State is EntityState.Added or EntityState.Modified)
            {
                entry.Entity.UpdatedAtUtc = DateTimeOffset.UtcNow;
            }
        }

        foreach (var entry in ChangeTracker.Entries<ClassRoom>())
        {
            if (entry.State == EntityState.Added && string.IsNullOrWhiteSpace(entry.Entity.TenantId))
            {
                entry.Entity.TenantId = tenantId;
            }

            if (entry.State is EntityState.Added or EntityState.Modified)
            {
                entry.Entity.UpdatedAtUtc = DateTimeOffset.UtcNow;
            }
        }

        foreach (var entry in ChangeTracker.Entries<Subject>())
        {
            if (entry.State == EntityState.Added && string.IsNullOrWhiteSpace(entry.Entity.TenantId))
            {
                entry.Entity.TenantId = tenantId;
            }

            if (entry.State is EntityState.Added or EntityState.Modified)
            {
                entry.Entity.UpdatedAtUtc = DateTimeOffset.UtcNow;
            }
        }

        foreach (var entry in ChangeTracker.Entries<Grade>())
        {
            if (entry.State == EntityState.Added && string.IsNullOrWhiteSpace(entry.Entity.TenantId))
            {
                entry.Entity.TenantId = tenantId;
            }

            if (entry.State is EntityState.Added or EntityState.Modified)
            {
                entry.Entity.UpdatedAtUtc = DateTimeOffset.UtcNow;
            }
        }

        foreach (var entry in ChangeTracker.Entries<Payment>())
        {
            if (entry.State == EntityState.Added && string.IsNullOrWhiteSpace(entry.Entity.TenantId))
            {
                entry.Entity.TenantId = tenantId;
            }

            if (entry.State is EntityState.Added or EntityState.Modified)
            {
                entry.Entity.UpdatedAtUtc = DateTimeOffset.UtcNow;
            }
        }

        foreach (var entry in ChangeTracker.Entries<StaffMember>())
        {
            if (entry.State == EntityState.Added && string.IsNullOrWhiteSpace(entry.Entity.TenantId))
            {
                entry.Entity.TenantId = tenantId;
            }

            if (entry.State is EntityState.Added or EntityState.Modified)
            {
                entry.Entity.UpdatedAtUtc = DateTimeOffset.UtcNow;
            }
        }

        foreach (var entry in ChangeTracker.Entries<TimetableEntry>())
        {
            if (entry.State == EntityState.Added && string.IsNullOrWhiteSpace(entry.Entity.TenantId))
            {
                entry.Entity.TenantId = tenantId;
            }

            if (entry.State is EntityState.Added or EntityState.Modified)
            {
                entry.Entity.UpdatedAtUtc = DateTimeOffset.UtcNow;
            }
        }
    }
}
