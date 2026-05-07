using SchoolManager.BuildingBlocks.Multitenancy;

namespace SchoolManager.Modules.Academics;

public sealed class SchoolSettings : ITenantEntity
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string TenantId { get; set; } = string.Empty;

    /// <summary>Clé du paramètre (ex: "school_name", "school_address").</summary>
    public string Key { get; set; } = string.Empty;

    /// <summary>Valeur du paramètre (texte brut).</summary>
    public string Value { get; set; } = string.Empty;

    public DateTimeOffset UpdatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
