import { decompress as zstdDecompress } from "fzstd";

import { UserFacingError } from "@/lib/api";

// An .apkg is a zip of the collection database plus every image and sound in the deck. Only
// the collection is needed (media isn't imported), so it is read straight out of the zip
// without loading the rest: media-heavy packages run to hundreds of megabytes.

// Newest format first. Packages from current Anki also carry a placeholder collection.anki2
// that only says "please update Anki".
const COLLECTION_NAMES = ["collection.anki21b", "collection.anki21", "collection.anki2"];

const END_OF_DIRECTORY = 0x06054b50;
const DIRECTORY_ENTRY = 0x02014b50;
const LOCAL_HEADER = 0x04034b50;
const ZSTD_MAGIC = 0xfd2fb528;

interface ZipEntry {
  name: string;
  method: number;
  compressedSize: number;
  headerOffset: number;
}

const notAPackage = () =>
  new UserFacingError(
    "This file isn't an Anki deck package. In Anki, use File → Export with “Anki Deck Package (.apkg)”.",
  );

async function view(file: Blob, start: number, end: number): Promise<DataView> {
  return new DataView(await file.slice(start, end).arrayBuffer());
}

async function readDirectory(file: Blob): Promise<ZipEntry[]> {
  // The end-of-directory record is the last 22 bytes, unless a comment (up to 64 KiB) follows.
  const tailStart = Math.max(0, file.size - 22 - 0xffff);
  const tail = await view(file, tailStart, file.size);
  let end = -1;
  for (let offset = tail.byteLength - 22; offset >= 0; offset--) {
    if (tail.getUint32(offset, true) === END_OF_DIRECTORY) {
      end = offset;
      break;
    }
  }
  if (end < 0) throw notAPackage();
  const size = tail.getUint32(end + 12, true);
  const start = tail.getUint32(end + 16, true);
  if (start === 0xffffffff) {
    throw new UserFacingError("This package is over 4 GB. Export a smaller deck from Anki.");
  }
  const directory = await view(file, start, start + size);
  const decoder = new TextDecoder();
  const entries: ZipEntry[] = [];
  for (let offset = 0; offset + 46 <= directory.byteLength;) {
    if (directory.getUint32(offset, true) !== DIRECTORY_ENTRY) break;
    const nameLength = directory.getUint16(offset + 28, true);
    const name = decoder.decode(
      new Uint8Array(directory.buffer, directory.byteOffset + offset + 46, nameLength),
    );
    entries.push({
      name,
      method: directory.getUint16(offset + 10, true),
      compressedSize: directory.getUint32(offset + 20, true),
      headerOffset: directory.getUint32(offset + 42, true),
    });
    offset +=
      46 +
      nameLength +
      directory.getUint16(offset + 30, true) +
      directory.getUint16(offset + 32, true);
  }
  return entries;
}

async function readEntry(file: Blob, entry: ZipEntry): Promise<Uint8Array<ArrayBuffer>> {
  const header = await view(file, entry.headerOffset, entry.headerOffset + 30);
  if (header.getUint32(0, true) !== LOCAL_HEADER) throw notAPackage();
  const dataStart =
    entry.headerOffset + 30 + header.getUint16(26, true) + header.getUint16(28, true);
  const data = file.slice(dataStart, dataStart + entry.compressedSize);
  if (entry.method === 0) return new Uint8Array(await data.arrayBuffer());
  if (entry.method !== 8) throw notAPackage();
  const inflated = data.stream().pipeThrough(new DecompressionStream("deflate-raw"));
  return new Uint8Array(await new Response(inflated).arrayBuffer());
}

// Returns the package's collection database, gzipped for the upload.
export async function extractAnkiCollection(file: Blob): Promise<Blob> {
  const entries = await readDirectory(file);
  const entry = COLLECTION_NAMES.map((name) => entries.find((e) => e.name === name)).find(
    (found) => found !== undefined,
  );
  if (!entry) throw notAPackage();
  let collection = await readEntry(file, entry);
  if (
    collection.byteLength >= 4 &&
    new DataView(collection.buffer).getUint32(0, true) === ZSTD_MAGIC
  ) {
    // A copy, so the bytes sit in a plain ArrayBuffer as Blob requires.
    collection = new Uint8Array(zstdDecompress(collection));
  }
  const gzipped = new Blob([collection]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Blob([await new Response(gzipped).arrayBuffer()], { type: "application/gzip" });
}
