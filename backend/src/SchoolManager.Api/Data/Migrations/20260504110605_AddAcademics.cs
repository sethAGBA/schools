using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SchoolManager.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddAcademics : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "classes",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    tenant_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    academic_year = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    level = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    capacity = table.Column<int>(type: "integer", nullable: false),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_classes", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "grades",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    tenant_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    student_id = table.Column<Guid>(type: "uuid", nullable: false),
                    subject_id = table.Column<Guid>(type: "uuid", nullable: false),
                    period = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    devoir_note = table.Column<double>(type: "double precision", nullable: true),
                    composition_note = table.Column<double>(type: "double precision", nullable: true),
                    average = table.Column<double>(type: "double precision", nullable: true),
                    teacher_comment = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    class_average = table.Column<double>(type: "double precision", nullable: true),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_grades", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "subjects",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    tenant_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    coefficient = table.Column<double>(type: "double precision", nullable: false),
                    class_room_id = table.Column<Guid>(type: "uuid", nullable: false),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_subjects", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_classes_tenant_id_name_academic_year",
                table: "classes",
                columns: new[] { "tenant_id", "name", "academic_year" });

            migrationBuilder.CreateIndex(
                name: "IX_grades_tenant_id_student_id_period",
                table: "grades",
                columns: new[] { "tenant_id", "student_id", "period" });

            migrationBuilder.CreateIndex(
                name: "IX_grades_tenant_id_subject_id_period",
                table: "grades",
                columns: new[] { "tenant_id", "subject_id", "period" });

            migrationBuilder.CreateIndex(
                name: "IX_subjects_tenant_id_class_room_id",
                table: "subjects",
                columns: new[] { "tenant_id", "class_room_id" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "classes");

            migrationBuilder.DropTable(
                name: "grades");

            migrationBuilder.DropTable(
                name: "subjects");
        }
    }
}
