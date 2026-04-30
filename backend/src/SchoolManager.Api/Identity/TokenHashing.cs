using System.Security.Cryptography;
using System.Text;

namespace SchoolManager.Api.Identity;

public static class TokenHashing
{
    public static string Sha256(string value)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(bytes);
    }
}
