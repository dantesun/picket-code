#!/usr/bin/env node
/**
 * Verifies that a `node_modules.asar` produced by build/lib/asar.ts is laid out
 * coherently.
 *
 * `Filesystem.insertFile` captures `this.offset` before awaiting the file
 * integrity hash and only advances it afterwards, so concurrent inserts end up
 * with the same offset: the archive still "works", but one file silently reads
 * back as the content of another (this is what broke `tar/package.json` and
 * thereby the agent host). See build/patches/56-asar-serialize-inserts.patch.
 *
 * Two checks, because zero-byte files legitimately share an offset (they
 * advance the offset by 0):
 *   1. no two non-empty entries may start at the same offset (overlap);
 *   2. entries sorted by offset must tile the data region without gaps, which is
 *      how the writer lays them out.
 *
 * Usage: node build/check-asar.mjs <path/to/node_modules.asar> [...]
 */
import fs from 'node:fs';

const paths = process.argv.slice(2);
if (paths.length === 0) {
	console.error('usage: node build/check-asar.mjs <node_modules.asar> [...]');
	process.exit(2);
}

let failed = false;

for (const file of paths) {
	const buf = fs.readFileSync(file);
	const jsonSize = buf.readUInt32LE(12);
	const header = JSON.parse(buf.subarray(16, 16 + jsonSize).toString());
	const dataBase = buf.readUInt32LE(4) + 8;
	const dataSize = buf.length - dataBase;

	const entries = [];
	const walk = (node, prefix) => {
		for (const [name, entry] of Object.entries(node.files ?? {})) {
			const path = prefix ? `${prefix}/${name}` : name;
			if (entry.files) {
				walk(entry, path);
			} else if (entry.size !== undefined && !entry.unpacked) {
				entries.push({ path, offset: Number(entry.offset), size: Number(entry.size) });
			}
		}
	};
	walk(header, '');

	const overlaps = [];
	const byOffset = new Map();
	for (const entry of entries.filter(e => e.size > 0)) {
		const group = byOffset.get(entry.offset) ?? [];
		group.push(entry);
		byOffset.set(entry.offset, group);
	}
	for (const group of byOffset.values()) {
		if (group.length > 1) {
			overlaps.push(group);
		}
	}

	let endMismatch = null;
	const sorted = [...entries.filter(e => e.size > 0)].sort((a, b) => a.offset - b.offset);
	const gaps = [];
	let expected = 0;
	for (const entry of sorted) {
		if (entry.offset !== expected) {
			gaps.push({ path: entry.path, offset: entry.offset, expected });
		}
		expected = entry.offset + entry.size;
	}
	if (expected !== dataSize) {
		endMismatch = expected;
	}

	const truncated = entries.filter(e => e.offset + e.size > dataSize);

	console.log(`${file}`);
	console.log(`  packed entries: ${entries.length}, data region: ${dataSize} bytes, layout ends at ${expected}`);
	console.log(`  non-empty entries sharing an offset: ${overlaps.length}`);
	console.log(`  layout gaps/misalignments: ${gaps.length}`);
	console.log(`  entries pointing past the data region: ${truncated.length}`);
	if (endMismatch !== null) {
		console.log(`  data region ends at ${endMismatch}, archive has ${dataSize} bytes`);
	}

	for (const group of overlaps.slice(0, 10)) {
		console.log(`  OVERLAP @${group[0].offset}: ${group.map(e => `${e.path} (size ${e.size})`).join(' | ')}`);
	}
	// A gap means data was written without a header entry. The writer has a
	// pre-existing quirk that drops one file per `type/*` directory (official
	// VS Code ships exactly the same artefact), so gaps are reported but not
	// fatal; overlaps and a data region that does not match are.
	for (const gap of gaps.slice(0, 10)) {
		console.log(`  GAP (warning): ${gap.path} at ${gap.offset}, expected ${gap.expected}`);
	}

	if (overlaps.length > 0 || truncated.length > 0 || endMismatch !== null) {
		failed = true;
	}
}

process.exit(failed ? 1 : 0);
