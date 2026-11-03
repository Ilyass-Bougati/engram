export function plural(count: number, singular: string, pluralForm = `${singular}s`): string {
  return `${String(count)} ${count === 1 ? singular : pluralForm}`;
}

export function studyCountsText(due: number, fresh: number): string {
  return `${due === 0 ? "Nothing due" : `${String(due)} due`} · ${String(fresh)} new`;
}

const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: "medium" });
const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
  dateStyle: "medium",
  timeStyle: "short",
});
const relativeFormat = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });

export function formatDate(iso: string): string {
  return dateFormat.format(new Date(iso));
}

export function formatDateTime(iso: string): string {
  return dateTimeFormat.format(new Date(iso));
}

const UNITS: [Intl.RelativeTimeFormatUnit, number][] = [
  ["day", 86_400_000],
  ["hour", 3_600_000],
  ["minute", 60_000],
];

export function formatRelative(iso: string, now = Date.now()): string {
  const difference = new Date(iso).getTime() - now;
  for (const [unit, milliseconds] of UNITS) {
    if (Math.abs(difference) >= milliseconds || unit === "minute") {
      return relativeFormat.format(Math.round(difference / milliseconds), unit);
    }
  }
  return relativeFormat.format(0, "minute");
}

// The first line of a card's Markdown, for one-line previews in lists.
export function firstLine(markdown: string): string {
  const line =
    markdown.split("\n").find((text) => text.trim() !== "" && !text.trim().startsWith("```")) ?? "";
  return line.replace(/^#{1,6}\s+/, "").trim();
}
