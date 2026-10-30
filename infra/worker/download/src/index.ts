/**
 * Serves release archives from R2 on the website hostname.
 *
 * `picket-code.noware.cn` is a Cloudflare Pages custom domain, so the site keeps
 * being served from Pages for every other path. This worker only answers for
 * `/picket-code-*`, which is the naming scheme of the published artifacts, and
 * streams the object out of the `picket-releases` bucket.
 *
 * File names carry the version (`picket-code-v1.143.1-p4-win32-x64.zip`), so the
 * body behind a given URL never changes and the response can be cached forever.
 *
 * Cloudflare does not cache worker responses on its own, so every download used
 * to stream the whole object out of the bucket: the edge that answers Chinese
 * clients sits in Los Angeles while the bucket answered from APAC, and each chunk
 * paid a trans-Pacific round trip. Full-object GETs now go into the edge cache, so
 * a cold object touches R2 once per location instead of once per download.
 */

interface R2Range {
	offset: number;
	length: number;
}

interface R2Object {
	readonly key: string;
	readonly size: number;
	readonly httpEtag: string;
	readonly range?: R2Range;
	readonly body: ReadableStream;
	writeHttpMetadata(headers: Headers): void;
}

interface R2Bucket {
	get(key: string, options?: { range?: Headers }): Promise<R2Object | null>;
}

interface ExecutionContext {
	waitUntil(promise: Promise<unknown>): void;
}

interface Cache {
	match(request: Request): Promise<Response | undefined>;
	put(request: Request, response: Response): Promise<void>;
}

declare const caches: { readonly default: Cache };

export interface Env {
	RELEASES: R2Bucket;
}

const CONTENT_TYPES: [string, string][] = [
	['.tar.gz', 'application/gzip'],
	['.zip', 'application/zip'],
];

function contentTypeFor(key: string): string {
	for (const [suffix, type] of CONTENT_TYPES) {
		if (key.endsWith(suffix)) {
			return type;
		}
	}
	return 'text/plain; charset=utf-8';
}

function notFound(): Response {
	return new Response('Not Found\n', {
		status: 404,
		headers: { 'content-type': 'text/plain; charset=utf-8' },
	});
}

// The cache key is the URL alone: the artifact behind it is immutable, and a
// range or a query string must never produce a different body under it.
function cacheKeyFor(request: Request): Request {
	return new Request(new URL(request.url).toString(), { method: 'GET' });
}

function withCacheStatus(response: Response, value: 'HIT' | 'MISS'): Response {
	const headers = new Headers(response.headers);
	headers.set('x-picket-cache', value);
	return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

/**
 * Fills the edge cache from a second read of the object.
 *
 * Calling `cache.put` on the response that is being streamed to the client would
 * tee the body, and a 200 MB body consumed by the cache faster than by a slow
 * client buffers the difference in memory. Reading twice costs one extra R2 GET
 * on a cold object and keeps both streams independent.
 */
async function fillCache(env: Env, cache: Cache, request: Request, key: string, headers: Headers): Promise<void> {
	const object = await env.RELEASES.get(key);
	if (!object) {
		return;
	}
	await cache.put(cacheKeyFor(request), new Response(object.body, { status: 200, headers }));
}

export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
		if (request.method !== 'GET' && request.method !== 'HEAD') {
			return new Response('Method Not Allowed\n', {
				status: 405,
				headers: { allow: 'GET, HEAD', 'content-type': 'text/plain; charset=utf-8' },
			});
		}

		const key = decodeURIComponent(new URL(request.url).pathname.replace(/^\/+/, ''));
		// The route only covers `/picket-code-*`, but the check keeps the worker safe
		// if the route is ever widened: no traversal, no other objects.
		if (!key.startsWith('picket-code-') || key.includes('..')) {
			return notFound();
		}

		// R2 reports a full-object range even for HEAD; only a client Range makes
		// the response partial.
		const wantsRange = request.headers.has('range');
		const cache = caches.default;
		const cacheable = request.method === 'GET' && !wantsRange;

		if (cacheable) {
			const hit = await cache.match(cacheKeyFor(request));
			if (hit) {
				return withCacheStatus(hit, 'HIT');
			}
		}

		const object = await env.RELEASES.get(key, { range: request.headers });
		if (!object) {
			return notFound();
		}

		const headers = new Headers();
		object.writeHttpMetadata(headers);
		headers.set('etag', object.httpEtag);
		headers.set('accept-ranges', 'bytes');
		if (key.endsWith('-SHA256SUMS')) {
			headers.set('content-type', 'text/plain; charset=utf-8');
		} else if (!headers.has('content-type')) {
			headers.set('content-type', contentTypeFor(key));
		}
		headers.set('cache-control', 'public, max-age=31536000, immutable');

		let status = 200;
		if (wantsRange && object.range) {
			const { offset, length } = object.range;
			status = 206;
			headers.set('content-length', String(length));
			headers.set('content-range', `bytes ${offset}-${offset + length - 1}/${object.size}`);
		} else {
			headers.set('content-length', String(object.size));
		}

		if (cacheable && status === 200) {
			ctx.waitUntil(fillCache(env, cache, request, key, headers).catch(() => undefined));
		}

		const body = request.method === 'HEAD' ? null : object.body;
		const response = new Response(body, { status, headers });
		return cacheable ? withCacheStatus(response, 'MISS') : response;
	},
};
