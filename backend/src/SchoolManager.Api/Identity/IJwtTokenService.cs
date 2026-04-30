using SchoolManager.Modules.Identity.Domain;

namespace SchoolManager.Api.Identity;

public interface IJwtTokenService
{
    string GenerateAccessToken(AppUser user);
}
