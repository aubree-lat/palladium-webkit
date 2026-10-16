import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const [runtime, sourceArgument] = process.argv.slice(2);
if (!runtime || !sourceArgument) {
  process.stderr.write("usage: relocate-linux-runtime.mjs RUNTIME SOURCE_PREFIX\n");
  process.exit(2);
}

const sourceRoot = sourceArgument.replace(/\/+$/, "");
const destinationRoot = "/usr/lib/palladium/runtime";
const mappings = [
  [
    `${sourceRoot}/lib/webkit2gtk-4.1/injected-bundle/`,
    `${destinationRoot}/lib/webkit2gtk-4.1/injected-bundle/`
  ],
  [`${sourceRoot}/lib/webkit2gtk-4.1`, `${destinationRoot}/lib/webkit2gtk-4.1`],
  [`${sourceRoot}/share/locale`, `${destinationRoot}/share/locale`],
  [`${sourceRoot}/share`, `${destinationRoot}/share`],
  [`${sourceRoot}/lib`, `${destinationRoot}/lib`]
];
const library = join(runtime, "lib", "libwebkit2gtk-4.1.so.0");
const contents = await readFile(library);

for (const [source, destination] of mappings) {
  const sourceBytes = Buffer.from(source);
  const destinationBytes = Buffer.from(destination);
  if (destinationBytes.length > sourceBytes.length) {
    throw new Error(`runtime destination is longer than embedded build path: ${source}`);
  }
  let cursor = 0;
  let replacements = 0;
  while (cursor < contents.length) {
    const index = contents.indexOf(sourceBytes, cursor);
    if (index === -1) break;
    const end = index + sourceBytes.length;
    if (contents[end] === 0) {
      destinationBytes.copy(contents, index);
      contents.fill(0, index + destinationBytes.length, end);
      replacements += 1;
    }
    cursor = end;
  }
  if (replacements === 0) throw new Error(`embedded WebKit runtime path was not found: ${source}`);
}

if (contents.includes(Buffer.from(sourceRoot))) {
  throw new Error(`embedded WebKit build prefix remains after relocation: ${sourceRoot}`);
}

await writeFile(library, contents);
process.stdout.write(`Relocated private WebKit runtime to ${destinationRoot}\n`);
