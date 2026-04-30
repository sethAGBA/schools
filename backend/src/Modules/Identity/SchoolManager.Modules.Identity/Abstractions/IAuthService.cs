namespace SchoolManager.Modules.Identity.Abstractions;

public interface IAuthService
{
    Task<AuthResult> LoginAsync(string email, string password, CancellationToken cancellationToken = default);
    Task<AuthResult> RefreshAsync(string refreshToken, CancellationToken cancellationToken = default);
    Task<AuthResult> LogoutAsync(string refreshToken, CancellationToken cancellationToken = default);
}

public sealed record AuthResult(
    bool Succeeded,
    string? AccessToken,
    string? RefreshToken,
    string? Error);
