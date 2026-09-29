using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SchoolManager.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddCategoryIdToSubjects : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "category_id",
                table: "subjects",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_subjects_category_id",
                table: "subjects",
                column: "category_id");

            migrationBuilder.AddForeignKey(
                name: "FK_subjects_subject_categories_category_id",
                table: "subjects",
                column: "category_id",
                principalTable: "subject_categories",
                principalColumn: "id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_subjects_subject_categories_category_id",
                table: "subjects");

            migrationBuilder.DropIndex(
                name: "IX_subjects_category_id",
                table: "subjects");

            migrationBuilder.DropColumn(
                name: "category_id",
                table: "subjects");
        }
    }
}
