using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SchoolManager.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddStaffTable : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "staff",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    tenant_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    name = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    role = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    department = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    phone = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    email = table.Column<string>(type: "character varying(320)", maxLength: 320, nullable: false),
                    qualifications = table.Column<string>(type: "text", nullable: true),
                    courses = table.Column<string>(type: "text", nullable: true),
                    classes = table.Column<string>(type: "text", nullable: true),
                    status = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    hire_date = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    type_role = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    first_name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: true),
                    last_name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: true),
                    gender = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true),
                    birth_date = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true),
                    birth_place = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    nationality = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    address = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    photo_path = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    matricule = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    id_number = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    social_security_number = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    marital_status = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    number_of_children = table.Column<int>(type: "integer", nullable: true),
                    region = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    levels = table.Column<string>(type: "text", nullable: true),
                    highest_degree = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    specialty = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    experience_years = table.Column<int>(type: "integer", nullable: true),
                    previous_institution = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: true),
                    contract_type = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    base_salary = table.Column<double>(type: "double precision", nullable: true),
                    weekly_hours = table.Column<int>(type: "integer", nullable: true),
                    supervisor = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    retirement_date = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true),
                    documents = table.Column<string>(type: "text", nullable: true),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_staff", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_staff_tenant_id_matricule",
                table: "staff",
                columns: new[] { "tenant_id", "matricule" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_staff_tenant_id_name",
                table: "staff",
                columns: new[] { "tenant_id", "name" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "staff");
        }
    }
}
