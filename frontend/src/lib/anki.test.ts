import { readFileSync } from "node:fs";
import { gunzipSync } from "node:zlib";

import { describe, expect, test } from "vitest";

import { extractAnkiCollection } from "@/lib/anki";

// A real package from current Anki: zstd-compressed collection.anki21b, a placeholder
// collection.anki2, and media.
const PACKAGE = readFileSync(new URL("../../e2e/fixtures/geography.apkg", import.meta.url));

describe("extractAnkiCollection", () => {
  test("pulls the newest collection out of the package and gzips it", async () => {
    const upload = await extractAnkiCollection(new Blob([PACKAGE]));
    expect(upload.type).toBe("application/gzip");
    const database = gunzipSync(new Uint8Array(await upload.arrayBuffer()));
    expect(database.subarray(0, 16).toString("latin1")).toBe("SQLite format 3\0");
    // The real collection has the schema 18 note type tables; the placeholder doesn't.
    expect(database.includes("CREATE TABLE notetypes")).toBe(true);
  });

  test("refuses files that aren't packages", async () => {
    await expect(extractAnkiCollection(new Blob(['{"format": "engram-deck"}']))).rejects.toThrow(
      "isn't an Anki deck package",
    );
  });
});
