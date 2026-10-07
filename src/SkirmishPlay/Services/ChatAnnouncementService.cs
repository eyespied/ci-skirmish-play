using TaleWorlds.Core;

namespace SkirmishPlay.Services
{
    internal static class ChatAnnouncementService
    {
        // MP.ChatLog.Text only ships a few named styles. HeadshotTitle.Text is the
        // built-in bright highlight (magenta) that works on all native clients.
        private const string HighlightStyle = "HeadshotTitle.Text";

        public static string BuildSetMapAnnouncement(
            string mapId,
            BasicCultureObject? cultureTeam1,
            BasicCultureObject? cultureTeam2)
        {
            string mapSegment = Highlight(mapId);

            if (cultureTeam1 == null || cultureTeam2 == null)
            {
                return $"Switching to {mapSegment}";
            }

            string team1Segment = Highlight(CultureCommandService.GetDisplayName(cultureTeam1));
            string team2Segment = Highlight(CultureCommandService.GetDisplayName(cultureTeam2));

            return $"Switching to {mapSegment} — {team1Segment} vs {team2Segment}";
        }

        private static string Highlight(string text)
        {
            return $"<span style=\"{HighlightStyle}\"><b>{text}</b></span>";
        }
    }
}
