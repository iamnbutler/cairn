// Serves the static site, the package pages (registry.js), and /m/<key> from the cairn-media
// R2 bucket. /docs/<pkg>/<version>/ is registry.js's placeholder: nothing here or there proxies
// a registry's docs, since HTML a publisher uploaded would run as this origin. A static file always wins: the Worker runs only for paths that no asset matched.
// Media keys are content-hashed, so they cache forever. Range and conditional
// requests pass through to R2: video seeking needs them, and Safari won't play
// video without range support.
import { route } from "./registry.js";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    // A package version's card is drawn when the site builds; one published since has none yet.
    if (url.pathname.startsWith("/og/pkg/")) return env.ASSETS.fetch(new Request(new URL("/og/packages.png", url)));
    if (url.pathname === "/packages" || url.pathname.startsWith("/packages/") || url.pathname.startsWith("/docs/")) {
      if (request.method !== "GET" && request.method !== "HEAD") return env.ASSETS.fetch(request);
      try {
        return (await route(request, env)) ?? env.ASSETS.fetch(request);
      } catch (err) {
        console.error(err);
        return new Response("The package registry didn't answer. Try again in a minute.", { status: 502 });
      }
    }
    if (!url.pathname.startsWith("/m/")) return env.ASSETS.fetch(request);
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("method not allowed", { status: 405 });
    }
    const key = decodeURIComponent(url.pathname.slice(3));
    const object = await env.MEDIA.get(key, { range: request.headers, onlyIf: request.headers });
    if (object === null) return new Response("not found", { status: 404 });

    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set("etag", object.httpEtag);
    headers.set("accept-ranges", "bytes");
    headers.set("cache-control", "public, max-age=31536000, immutable");
    if (!("body" in object)) return new Response(null, { status: 304, headers });

    let status = 200;
    if (object.range && request.headers.has("range")) {
      const { offset = 0, length = object.size - offset } = object.range;
      headers.set("content-range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
      headers.set("content-length", String(length));
      status = 206;
    } else {
      headers.set("content-length", String(object.size));
    }
    return new Response(request.method === "HEAD" ? null : object.body, { status, headers });
  },
};
