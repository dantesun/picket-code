/**
 * Serves release archives from R2 on the website hostname.
 *
 * `picket-code.noware.cn` is a Cloudflare Pages custom domain, so the site keeps
 * being served from Pages for every other path. This worker only answers for
 * `/picket-code-*`, which is the naming scheme of the published artifacts, and
 * streams the object straight out of the `picket-releases` bucket.
 *
 * File names carry the version (`picket-code-v1.143.1-p2-win32-x64.zip`), so the
 * body behind a given URL never changes and the response can be cached forever.
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

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
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

		const object = await env.RELEASES.get(key, { range: request.headers });
		if (!object) {
			return notFound();
		}

		const headers = new Headers();
		object.writeHttpMetadata(headers);
		headers.set('etag', object.httpEtag);
		headers.set('accept-ranges', 'bytes');
		// R2 reports a full-object range even for HEAD; only a client Range makes
		// the response partial.
		const wantsRange = request.headers.has('range');
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

		return new Response(request.method === 'HEAD' ? null : object.body, { status, headers });
	},
};
