# Search

The search circle in Hearth's top bar finds films and shows and opens them in the app that has them.

## What you'll see

- Type a title. Results show the title, year and a short description, plus, when posters are on, the poster and the
  services streaming it in the US ("Streaming on Disney Plus, Hulu").
- Each result has a button for every installed app that has the title (for example **Netflix**), which opens the app
  on that title. Profile Pairing picks your profile first, as usual.
- **More on Google TV** (or **Where to watch (Google TV)**) opens Google TV's page for the title, with its own Watch
  now buttons.
- Below the results: **Search HearthTube** and **Ask Google TV** (Google TV's own search, including Gemini for
  questions like "funny dinosaur movies").

## Where the results come from

| Source | What it provides | What it's sent |
|:---|:---|:---|
| [Wikidata](https://www.wikidata.org) (Wikimedia Foundation) | Titles, years, descriptions, and each title's ids in Netflix, Disney+, Apple TV, HBO Max, Paramount+ and Google TV | Your search text |
| [TMDB](https://www.themoviedb.org) (optional) | Posters and where a title is streaming in the US (data from [JustWatch](https://www.justwatch.com)) | The TMDB id of each result shown, with Hearth's API key |

No account is involved and Hearth keeps nothing beyond the current session. Like any website, both services see the
TV's internet address when it asks them something.

## Limitations

**Wikidata (titles and app links)**
- It's volunteer-maintained. Popular titles are well covered; newer or obscure ones may be missing, or may lack the
  id for an app, so no button appears for that app. Google TV's page is always offered as a fallback.
- It records that a title *has* a Netflix (or other) id, not that it's streaming there today. A title that has left
  a service may still get a button, and the app then shows its own "not available" page.
- Results are in English and matched by title, so a search can also return unrelated things with the same name; Hearth
  shows only films and shows.
- Wikidata limits how often it can be asked. Hearth waits until you pause typing and caches results, but very rapid
  searching can be slowed down.
- Direct buttons exist for Netflix, Apple TV, HBO Max and Paramount+. Disney+ no longer opens titles by the ids Wikidata
  has, so Disney+ titles open through Google TV's page (one extra press on its Watch now). Apple TV starts playing the
  title rather than showing its page. Paramount+ ids are rare in Wikidata, so its button seldom appears.
- Links into each app depend on that app's own link format, which can change in an app update (the same kind of
  fragility as [Profile Pairing](profile-pairing.md)). When an app can't open a link, use Google TV's page instead.

**TMDB (posters and "streaming on")**
- Needs an API key. Official Hearth releases include one; if yours doesn't (a build of your own, or a fork), add a free
  key of your own in **Settings → Search**. Without a key, search works without posters and nothing is sent to TMDB.
- Free for personal, non-commercial use under [TMDB's API terms](https://www.themoviedb.org/api-terms-of-use). Hearth
  shows the required notice: *This product uses the TMDB API but is not endorsed or certified by TMDB.*
- A key built into an app can be extracted from it. That's accepted practice for free, read-only TMDB keys; if one is
  ever abused, it's revoked and replaced in the next release.
- TMDB limits request rates; posters may fill in slowly or not at all if it's busy.
- "Streaming on" is US subscription services only (not rentals, purchases or other countries), comes from JustWatch
  through TMDB, and can lag behind a service adding or removing a title. It's for information: the app buttons come
  from Wikidata, not from this list.

**Not possible**
- Searching inside Netflix, Disney+ and the other apps directly: they don't let other apps search their catalogs.
- Showing Google TV's own search results inside Hearth: Google TV keeps them to itself. **Ask Google TV** opens them in
  Google TV instead.
