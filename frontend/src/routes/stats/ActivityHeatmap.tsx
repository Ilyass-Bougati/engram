import { useLayoutEffect, useRef } from "react";

import { plural } from "@/lib/format";
import type { Stats } from "@/lib/types";
import { dayKey, parseDay, TableView, useChartTooltip } from "@/routes/stats/chart";

const CELL = 11;
const GAP = 3;
const STEP = CELL + GAP;
const LEFT = 30;
const TOP = 18;
const WEEKS = 53;

const dayFormat = new Intl.DateTimeFormat(undefined, {
  weekday: "short",
  month: "short",
  day: "numeric",
  year: "numeric",
});
const monthFormat = new Intl.DateTimeFormat(undefined, { month: "short" });
const weekdayFormat = new Intl.DateTimeFormat(undefined, { weekday: "short" });

// Zero is the sunken surface; one to four steps of the pine ramp split the busiest day.
function level(reviews: number, busiest: number): number {
  if (reviews === 0) return 0;
  return Math.min(4, Math.max(1, Math.ceil((4 * reviews) / busiest)));
}

const fill = (step: number) =>
  step === 0 ? "var(--surface-sunken)" : `var(--chart-${String(step)})`;

export function ActivityHeatmap({ activity }: { activity: Stats["activity"] }) {
  const scroller = useRef<HTMLDivElement>(null);
  const tooltip = useChartTooltip();
  const counts = new Map(activity.days.map((day) => [day.date, day.reviews]));
  const busiest = Math.max(1, ...activity.days.map((day) => day.reviews));

  // Columns are weeks starting on Monday, ending with the week that holds today.
  const today = parseDay(activity.today);
  const start = new Date(today);
  start.setDate(today.getDate() - ((today.getDay() + 6) % 7) - (WEEKS - 1) * 7);
  const cells: { key: string; date: Date; week: number; weekday: number; reviews: number }[] = [];
  const months: { week: number; label: string }[] = [];
  for (let offset = 0; ; offset++) {
    const date = new Date(start);
    date.setDate(start.getDate() + offset);
    if (date > today) break;
    const week = Math.floor(offset / 7);
    const key = dayKey(date);
    cells.push({ key, date, week, weekday: offset % 7, reviews: counts.get(key) ?? 0 });
    // A month's label sits over the week of its first day, if it doesn't crowd the last one.
    const previous = months.at(-1);
    if (date.getDate() === 1 && week <= WEEKS - 3 && (!previous || week - previous.week >= 3)) {
      months.push({ week, label: monthFormat.format(date) });
    }
  }
  const width = LEFT + WEEKS * STEP;
  const height = TOP + 7 * STEP;

  useLayoutEffect(() => {
    // The newest weeks matter most; on narrow screens start scrolled to them.
    if (scroller.current) scroller.current.scrollLeft = scroller.current.scrollWidth;
  }, []);

  return (
    <div className="grid min-w-0 gap-4">
      <div data-chart className="relative min-w-0">
        <div ref={scroller} className="overflow-x-auto pb-1">
          <svg
            width={width}
            height={height}
            role="img"
            aria-label={`Reviews per day over the past year: ${plural(activity.total_reviews, "review")} in total.`}
            className="block"
          >
            {months.map((month) => (
              <text
                key={`${String(month.week)}-${month.label}`}
                x={LEFT + month.week * STEP}
                y={11}
                className="fill-muted-foreground text-xs"
              >
                {month.label}
              </text>
            ))}
            {[0, 2, 4].map((weekday) => {
              const date = new Date(start);
              date.setDate(start.getDate() + weekday);
              return (
                <text
                  key={weekday}
                  x={0}
                  y={TOP + weekday * STEP + CELL - 1}
                  className="fill-muted-foreground text-xs"
                >
                  {weekdayFormat.format(date)}
                </text>
              );
            })}
            {cells.map((cell) => (
              <rect
                key={cell.key}
                x={LEFT + cell.week * STEP}
                y={TOP + cell.weekday * STEP}
                width={CELL}
                height={CELL}
                rx={2}
                fill={fill(level(cell.reviews, busiest))}
                className="stroke-transparent stroke-2 [paint-order:stroke] hover:stroke-(--ink)"
                {...tooltip.markProps(plural(cell.reviews, "review"), dayFormat.format(cell.date))}
              />
            ))}
          </svg>
        </div>
        {tooltip.element}
      </div>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <TableView summary="Show as a table">
          <thead className="sticky top-0 bg-card">
            <tr className="border-b border-border">
              <th className="px-3 py-2 font-medium">Day</th>
              <th className="px-3 py-2 text-right font-medium">Reviews</th>
            </tr>
          </thead>
          <tbody>
            {[...activity.days].reverse().map((day) => (
              <tr key={day.date} className="border-b border-border last:border-0">
                <td className="px-3 py-1.5">{dayFormat.format(parseDay(day.date))}</td>
                <td className="px-3 py-1.5 text-right">{day.reviews.toLocaleString()}</td>
              </tr>
            ))}
          </tbody>
        </TableView>
        <div className="flex items-center gap-1.5 text-xs text-muted-foreground" aria-hidden>
          Less
          {[0, 1, 2, 3, 4].map((step) => (
            <span
              key={step}
              className="size-[11px] rounded-[2px]"
              style={{ background: fill(step) }}
            />
          ))}
          More
        </div>
      </div>
    </div>
  );
}
