using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SchoolManager.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddMockExams : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "type",
                table: "grades",
                type: "character varying(50)",
                maxLength: 50,
                nullable: false,
                defaultValue: "Devoir");

            migrationBuilder.CreateTable(
                name: "mock_exam_sessions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    tenant_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    order_index = table.Column<int>(type: "integer", nullable: false),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_mock_exam_sessions", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_mock_exam_sessions_tenant_id_name",
                table: "mock_exam_sessions",
                columns: new[] { "tenant_id", "name" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "mock_exam_sessions");

            migrationBuilder.DropColumn(
                name: "type",
                table: "grades");
        }
    }
}
