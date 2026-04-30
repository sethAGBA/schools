using System.Security.Cryptography;

namespace SchoolManager.Api.Identity;

public static class TokenGenerator
{
    public static string CreateSecureToken()
    {
        return Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));
    }
}
