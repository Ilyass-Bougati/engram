import type { CardStates } from "@/lib/types";
import { useChartTooltip } from "@/routes/stats/chart";

// The progression a card makes, so the ramp runs light (new) to dark (mature).
export const STATES: { key: keyof CardStates; label: string; help: string }[] = [
  { key: "new", label: "New", help: "not studied yet" },
  { key: "learning", label: "Learning", help: "in learning steps" },
  { key: "young", label: "Young", help: "interval under 21 days" },
  { key: "mature", label: "Mature", help: "interval of 21 days or more" },
];

export const stateColor = (index: number) => `var(--chart-${String(index + 1)})`;

export function CardStatesBar({
  states,
  compact = false,
}: {
  states: CardStates;
  compact?: boolean;
}) {
  const tooltip = useChartTooltip();
  const total = STATES.reduce((sum, state) => sum + states[state.key], 0);
  if (total === 0) return null;
  return (
    <div data-chart className="relative">
      {/* 2px of surface between segments separates them; no outlines. */}
      <div className={`flex gap-[2px] ${compact ? "h-2" : "h-6"}`}>
        {STATES.map((state, index) =>
          states[state.key] > 0 ? (
            <div
              key={state.key}
              className="min-w-1 first:rounded-l-[4px] last:rounded-r-[4px] hover:brightness-110"
              style={{ flexGrow: states[state.key], background: stateColor(index) }}
              tabIndex={compact ? undefined : 0}
              aria-label={
                compact ? undefined : `${state.label}: ${states[state.key].toLocaleString()}`
              }
              {...(compact
                ? {}
                : tooltip.markProps(
                    `${states[state.key].toLocaleString()} (${String(Math.round((100 * states[state.key]) / total))}%)`,
                    `${state.label}: ${state.help}`,
                  ))}
            />
          ) : null,
        )}
      </div>
      {tooltip.element}
    </div>
  );
}

export function CardStatesLegend({ states }: { states: CardStates }) {
  return (
    <dl className="grid grid-cols-2 gap-x-6 gap-y-3 sm:grid-cols-4">
      {STATES.map((state, index) => (
        <div key={state.key} className="grid gap-0.5">
          <dt className="flex items-center gap-2 text-sm text-muted-foreground">
            <span
              className="size-2.5 rounded-[2px]"
              style={{ background: stateColor(index) }}
              aria-hidden
            />
            {state.label}
          </dt>
          <dd className="pl-[18px] text-lg font-semibold tabular-nums">
            {states[state.key].toLocaleString()}
          </dd>
        </div>
      ))}
    </dl>
  );
}
