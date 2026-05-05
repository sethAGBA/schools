using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SchoolManager.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddTimetableEntries : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "timetable_entries",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    tenant_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    subject = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    teacher = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    class_name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    academic_year = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    day_of_week = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    start_time = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    end_time = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    room = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_timetable_entries", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_timetable_entries_tenant_id_class_name_academic_year",
                table: "timetable_entries",
                columns: new[] { "tenant_id", "class_name", "academic_year" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "timetable_entries");
        }
    }
}
