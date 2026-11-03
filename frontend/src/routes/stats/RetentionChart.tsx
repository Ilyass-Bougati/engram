import type { Stats } from "@/lib/types";
import {
  percent,
  rememberedText,
  TableView,
  useChartTooltip,
  useWidth,
} from "@/routes/stats/chart";

const HEIGHT = 180;
const LEFT = 40;
const BOTTOM = 24;
const TOP = 20;
const monthFormat = new Intl.DateTimeFormat(undefined, { month: "short" });
const longMonthFormat = new Intl.DateTimeFormat(undefined, { month: "long", year: "numeric" });

function monthDate(month: string): Date {
  const [year = 0, number = 1] = month.split("-").map(Number);
  return new Date(year, number - 1, 1);
}

// A column with a 4px rounded top, square on the baseline.
function columnPath(x: number, y: number, width: number, baseline: number): string {
  const r = Math.min(4, width / 2, baseline - y);
  return `M${String(x)},${String(baseline)}V${String(y + r)}Q${String(x)},${String(y)} ${String(x + r)},${String(y)}H${String(x + width - r)}Q${String(x + width)},${String(y)} ${String(x + width)},${String(y + r)}V${String(baseline)}Z`;
}

export function RetentionChart({ months }: { months: Stats["retention_by_month"] }) {
  const [ref, width] = useWidth<HTMLDivElement>();
  const tooltip = useChartTooltip();
  const plotWidth = Math.max(0, width - LEFT);
  const band = plotWidth / months.length;
  const column = Math.min(24, band * 0.6);
  const baseline = HEIGHT - BOTTOM;
  const y = (share: number) => baseline - share * (baseline - TOP);
  const latest = months.findLastIndex((month) => month.reviews > 0);
  // Every other month label when the bands get narrow.
  const labelEvery = band < 36 ? 2 : 1;

  return (
    <div className="grid min-w-0 gap-4">
      <div data-chart className="relative min-w-0">
        <div ref={ref}>
          {width > 0 && (
            <svg
              width={width}
              height={HEIGHT}
              role="img"
              aria-label="Retention by month for the past year."
              className="block"
            >
              {[0, 0.5, 1].map((share) => (
                <g key={share}>
                  <line
                    x1={LEFT}
                    x2={width}
                    y1={y(share)}
                    y2={y(share)}
                    stroke="var(--line)"
                    strokeWidth={1}
                  />
                  <text
                    x={LEFT - 8}
                    y={y(share) + 4}
                    textAnchor="end"
                    className="fill-muted-foreground text-xs tabular-nums"
                  >
                    {`${String(share * 100)}%`}
                  </text>
                </g>
              ))}
              {months.map((month, index) => {
                const x = LEFT + index * band;
                const share = month.reviews ? month.remembered / month.reviews : 0;
                const label = longMonthFormat.format(monthDate(month.month));
                return (
                  <g key={month.month}>
                    {month.reviews > 0 && (
                      <path
                        d={columnPath(x + (band - column) / 2, y(share), column, baseline)}
                        fill="var(--pine)"
                      />
                    )}
                    {index === latest && (
                      <text
                        x={x + band / 2}
                        y={y(share) - 6}
                        textAnchor="middle"
                        className="fill-foreground text-xs font-medium tabular-nums"
                      >
                        {percent(month)}
                      </text>
                    )}
                    {index % labelEvery === (months.length - 1) % labelEvery && (
                      <text
                        x={x + band / 2}
                        y={HEIGHT - 6}
                        textAnchor="middle"
                        className="fill-muted-foreground text-xs"
                      >
                        {monthFormat.format(monthDate(month.month))}
                      </text>
                    )}
                    {/* The whole band is the hit target, not just the painted column. */}
                    <rect
                      x={x}
                      y={TOP}
                      width={band}
                      height={baseline - TOP}
                      fill="transparent"
                      tabIndex={0}
                      aria-label={`${label}: ${month.reviews ? `${percent(month)}, ${rememberedText(month)}` : "no reviews"}`}
                      className="outline-none focus-visible:stroke-(--focus) focus-visible:stroke-2"
                      {...tooltip.markProps(
                        month.reviews ? percent(month) : "No reviews",
                        month.reviews ? `${label} · ${rememberedText(month)}` : label,
                      )}
                    />
                  </g>
                );
              })}
            </svg>
          )}
        </div>
        {tooltip.element}
      </div>
      <TableView summary="Show as a table">
        <thead className="sticky top-0 bg-card">
          <tr className="border-b border-border">
            <th className="px-3 py-2 font-medium">Month</th>
            <th className="px-3 py-2 text-right font-medium">Retention</th>
            <th className="px-3 py-2 text-right font-medium">Reviews</th>
          </tr>
        </thead>
        <tbody>
          {[...months].reverse().map((month) => (
            <tr key={month.month} className="border-b border-border last:border-0">
              <td className="px-3 py-1.5">{longMonthFormat.format(monthDate(month.month))}</td>
              <td className="px-3 py-1.5 text-right">{percent(month)}</td>
              <td className="px-3 py-1.5 text-right">{month.reviews.toLocaleString()}</td>
            </tr>
          ))}
        </tbody>
      </TableView>
    </div>
  );
}
