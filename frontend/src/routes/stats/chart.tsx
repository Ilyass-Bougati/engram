import { useLayoutEffect, useRef, useState, type ReactNode } from "react";

import type { Retention } from "@/lib/types";

// Study days arrive as YYYY-MM-DD; read them as local calendar dates so no timezone shifts
// them by a day.
export function parseDay(day: string): Date {
  const [year = 0, month = 1, date = 1] = day.split("-").map(Number);
  return new Date(year, month - 1, date);
}

export function dayKey(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${String(date.getFullYear())}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function percent(retention: Retention): string {
  if (retention.reviews === 0) return "–";
  return `${String(Math.round((100 * retention.remembered) / retention.reviews))}%`;
}

export function rememberedText(retention: Retention): string {
  return `${retention.remembered.toLocaleString()} of ${retention.reviews.toLocaleString()} remembered`;
}

export function useWidth<T extends HTMLElement>(): [React.RefObject<T | null>, number] {
  const ref = useRef<T>(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => {
      if (entry) setWidth(entry.contentRect.width);
    });
    observer.observe(element);
    return () => {
      observer.disconnect();
    };
  }, []);
  return [ref, width];
}

interface Tip {
  left: number;
  top: number;
  value: string;
  label: string;
}

// One tooltip per chart, shown for the hovered or focused mark: the value first, then what it
// is. It enhances only; every value is also in the chart's table. It is positioned within the
// mark's nearest element marked data-chart, which must be position: relative.
export function useChartTooltip() {
  const [tip, setTip] = useState<Tip | null>(null);

  function show(mark: Element, value: string, label: string) {
    const container = mark.closest("[data-chart]");
    if (!container) return;
    const box = container.getBoundingClientRect();
    const rect = mark.getBoundingClientRect();
    const center = rect.left - box.left + rect.width / 2;
    setTip({
      left: Math.min(Math.max(center, 72), box.width - 72),
      top: rect.top - box.top,
      value,
      label,
    });
  }

  const element: ReactNode = tip && (
    <div
      role="tooltip"
      className="pointer-events-none absolute z-10 grid -translate-x-1/2 -translate-y-full gap-0.5 rounded-md border border-border bg-card px-3 py-2 text-sm whitespace-nowrap shadow-sm"
      style={{ left: tip.left, top: tip.top - 8 }}
    >
      <strong className="font-semibold tabular-nums">{tip.value}</strong>
      <span className="text-muted-foreground">{tip.label}</span>
    </div>
  );

  return {
    element,
    // Spread on a mark: hover and keyboard focus show the same details.
    markProps: (value: string, label: string) => ({
      onPointerEnter: (event: React.PointerEvent) => {
        show(event.currentTarget, value, label);
      },
      onFocus: (event: React.FocusEvent) => {
        show(event.currentTarget, value, label);
      },
      onPointerLeave: () => {
        setTip(null);
      },
      onBlur: () => {
        setTip(null);
      },
    }),
  };
}

export function TableView({ summary, children }: { summary: string; children: ReactNode }) {
  return (
    <details className="text-sm">
      <summary className="w-fit cursor-pointer text-muted-foreground hover:text-foreground">
        {summary}
      </summary>
      <div className="mt-3 max-h-72 overflow-auto rounded-md border border-border">
        <table className="w-full text-left tabular-nums">{children}</table>
      </div>
    </details>
  );
}
