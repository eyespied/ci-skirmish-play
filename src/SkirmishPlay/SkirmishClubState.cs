namespace SkirmishPlay
{
    /// <summary>
    /// Process-wide flag: while active, live-round stats go to player_career_stats_skirmish
    /// and round/match rows are tagged is_skirmish_club = true.
    /// </summary>
    internal static class SkirmishClubState
    {
        public static bool IsActive { get; private set; }

        public static bool TrySetActive(bool active, out string message)
        {
            if (IsActive == active)
            {
                message = active
                    ? "Skirmish Club is already active."
                    : "Skirmish Club is already off.";
                return false;
            }

            IsActive = active;
            message = active
                ? "Skirmish Club STARTED — upcoming rounds tag club stats."
                : "Skirmish Club ENDED — upcoming rounds use normal career stats.";
            return true;
        }

        public static string StatusMessage =>
            IsActive
                ? "Skirmish Club is ACTIVE."
                : "Skirmish Club is OFF.";
    }
}
