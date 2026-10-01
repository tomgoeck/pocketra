// CORS-Brücke für das Freeware-Paket von Command & Conquer: Alarmstufe Rot.
//
// Warum es das gibt: Die Browser-Fassung von PocketRA kann das Paket nicht selbst beim Spiegel
// holen. Kein einziger der vier Spiegel aus OpenRAs Liste schickt `Access-Control-Allow-Origin`
// (nachgemessen, s. docs/WEB_INHALTE.md §2), und ohne diese Freigabe reicht der Browser die
// Antwort nicht an die Seite durch. In der App gibt es das Problem nicht, dort ist es ein
// gewöhnlicher Download.
//
// Warum als eigener Worker und nicht auf dem eigenen Server: Auf pocketra.net liegen auch
// fremde Projekte. Der Datenverkehr für dieses Paket soll von dieser Maschine fernbleiben.
//
// Zwei Selbstbeschränkungen, die bitte stehen bleiben:
//
//   1. KEIN offener Proxy. Nur die unten aufgezählten Pfade werden bedient, alles andere
//      bekommt 404. Ein offener CORS-Proxy wird binnen Tagen für fremde Zwecke missbraucht.
//   2. KEINE Zwischenspeicherung. `cacheEverything: false` und `cacheTtl: 0`, damit das Paket
//      durchläuft und nicht bei uns am Rand liegen bleibt.

const UPSTREAMS = {
  // Reihenfolge wie in OpenRAs Spiegelliste. Der erste, der antwortet, gewinnt.
  "/ra-quickinstall.zip": [
    "https://openra.ppmsite.com/ra-quickinstall.zip",
    "https://openra.baxxster.no/openra/ra-quickinstall.zip",
    "https://republic.community/hosted/files/command-and-conquer/openra/ra-quickinstall.zip",
    "https://openra.0x47.net/ra-quickinstall.zip",
  ],
};

const ALLOWED_ORIGINS = ["https://pocketra.net", "https://www.pocketra.net"];

function corsHeaders(origin) {
  const h = new Headers();
  // Nur die eigene Seite, nicht "*": das hier ist eine Brücke für PocketRA, kein Dienst für alle.
  h.set("Access-Control-Allow-Origin", ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0]);
  h.set("Vary", "Origin");
  h.set("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS");
  h.set("Access-Control-Allow-Headers", "Range");
  // Ohne das sieht die Seite bei einem Bereichsabruf weder Länge noch Bereich.
  h.set("Access-Control-Expose-Headers", "Content-Length, Content-Range, Accept-Ranges, ETag");
  h.set("Access-Control-Max-Age", "86400");
  return h;
}

export default {
  async fetch(request) {
    const origin = request.headers.get("Origin") || "";
    const url = new URL(request.url);
    const mirrors = UPSTREAMS[url.pathname];

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Nur GET, HEAD und OPTIONS.", { status: 405, headers: corsHeaders(origin) });
    }
    if (!mirrors) {
      return new Response("Unbekannter Pfad.", { status: 404, headers: corsHeaders(origin) });
    }

    // Bereichsabruf durchreichen, damit ein abgebrochener Download fortgesetzt werden kann.
    const fwd = new Headers();
    const range = request.headers.get("Range");
    if (range) fwd.set("Range", range);

    let last = null;
    for (const upstream of mirrors) {
      let res;
      try {
        res = await fetch(upstream, {
          method: request.method,
          headers: fwd,
          redirect: "follow",
          cf: { cacheEverything: false, cacheTtl: 0 },
        });
      } catch (e) {
        last = new Response("Spiegel nicht erreichbar: " + e, { status: 502, headers: corsHeaders(origin) });
        continue;
      }
      if (!res.ok && res.status !== 206) {
        last = new Response("Spiegel antwortete mit " + res.status, { status: 502, headers: corsHeaders(origin) });
        continue;
      }
      const out = corsHeaders(origin);
      for (const name of ["Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "ETag", "Last-Modified"]) {
        const v = res.headers.get(name);
        if (v) out.set(name, v);
      }
      out.set("Cache-Control", "no-store");
      // Der Rumpf wird gestreamt, nicht im Worker gesammelt: 13,5 MB sollen nicht in den Speicher.
      return new Response(res.body, { status: res.status, headers: out });
    }
    return last || new Response("Kein Spiegel erreichbar.", { status: 502, headers: corsHeaders(origin) });
  },
};
