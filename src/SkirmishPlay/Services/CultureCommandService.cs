using System;
using System.Linq;
using TaleWorlds.Core;
using TaleWorlds.ObjectSystem;

namespace SkirmishPlay.Services
{
    internal static class CultureCommandService
    {
        public static bool TryResolveCulture(string query, out BasicCultureObject culture, out string error)
        {
            culture = null!;
            error = string.Empty;

            if (string.IsNullOrWhiteSpace(query))
            {
                error = "Culture name is required.";
                return false;
            }

            string trimmed = query.Trim();
            var cultures = MBObjectManager.Instance.GetObjectTypeList<BasicCultureObject>();

            BasicCultureObject? match = cultures.FirstOrDefault(c =>
                string.Equals(c.StringId, trimmed, StringComparison.OrdinalIgnoreCase));
            if (match != null)
            {
                culture = match;
                return true;
            }

            match = cultures.FirstOrDefault(c =>
                c.Name != null && string.Equals(c.Name.ToString(), trimmed, StringComparison.OrdinalIgnoreCase));
            if (match != null)
            {
                culture = match;
                return true;
            }

            var partialMatches = cultures
                .Where(c =>
                    c.StringId.Contains(trimmed, StringComparison.OrdinalIgnoreCase) ||
                    (c.Name != null && c.Name.ToString().Contains(trimmed, StringComparison.OrdinalIgnoreCase)))
                .ToList();

            if (partialMatches.Count == 1)
            {
                culture = partialMatches[0];
                return true;
            }

            if (partialMatches.Count > 1)
            {
                error = $"Multiple cultures match '{query}': {string.Join(", ", partialMatches.Select(c => c.StringId))}";
                return false;
            }

            error = $"Unknown culture '{query}'. Try: {string.Join(", ", cultures.Select(c => c.StringId))}";
            return false;
        }

        public static string GetDisplayName(BasicCultureObject culture)
        {
            return culture.Name?.ToString() ?? culture.StringId;
        }
    }
}
