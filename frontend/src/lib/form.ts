import { UserFacingError } from "@/lib/api";

export function formText(form: FormData, name: string): string {
  const value = form.get(name);
  return typeof value === "string" ? value : "";
}

// Lowercased and deduplicated the same way the backend stores tags.
export function parseTags(text: string): string[] {
  return [
    ...new Set(
      text
        .split(/[\s,]+/)
        .map((tag) => tag.trim().toLowerCase())
        .filter(Boolean),
    ),
  ];
}

export function readJsonFile(file: File): Promise<unknown> {
  return file.text().then((text) => {
    try {
      return JSON.parse(text) as unknown;
    } catch (error) {
      if (error instanceof SyntaxError) {
        throw new UserFacingError(
          `${file.name} isn't valid JSON. Export a deck from Engram or check the file.`,
        );
      }
      throw error;
    }
  });
}
