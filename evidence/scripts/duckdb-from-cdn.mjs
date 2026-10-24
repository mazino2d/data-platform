// Cloudflare Pages rejects files over 25 MiB, and Evidence bundles DuckDB's
// WASM builds (33-38 MB). After `evidence build`, point the browser at the
// identical files on jsDelivr (same @duckdb/duckdb-wasm version, checked byte
// for byte) and drop them from the build. They are the public engine, not data.
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const build = 'build';
const assets = join(build, '_app/immutable/assets');
const pkg = 'node_modules/@duckdb/duckdb-wasm';
const { version } = JSON.parse(readFileSync(join(pkg, 'package.json'), 'utf8'));
const sha = (path) => createHash('sha256').update(readFileSync(path)).digest('hex');

const files = (dir) =>
  readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((e) => e.isFile())
    .map((e) => join(e.parentPath, e.name));
const texts = files(build).filter((f) => /\.(js|html|json)$/.test(f));

let moved = 0;
for (const name of readdirSync(assets)) {
  const match = /^(duckdb-[a-z]+)\.[^.]+\.wasm$/.exec(name);
  if (!match) continue;
  const dist = join(pkg, 'dist', `${match[1]}.wasm`);
  if (sha(join(assets, name)) !== sha(dist)) throw new Error(`${name} differs from ${dist}`);
  const local = `/_app/immutable/assets/${name}`;
  const cdn = `https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@${version}/dist/${match[1]}.wasm`;
  let refs = 0;
  for (const file of texts) {
    const text = readFileSync(file, 'utf8');
    if (!text.includes(local)) continue;
    writeFileSync(file, text.replaceAll(local, cdn));
    refs++;
  }
  if (refs === 0) throw new Error(`no reference to ${local}`);
  rmSync(join(assets, name));
  console.log(`${name} -> ${cdn} (${refs} reference${refs > 1 ? 's' : ''})`);
  moved++;
}
if (moved === 0) throw new Error('no DuckDB WASM file found in the build');
