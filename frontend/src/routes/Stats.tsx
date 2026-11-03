import { useQuery } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { Link } from "react-router";

import { PageHeader } from "@/components/PageHeader";
import { EmptyState, ErrorState, LoadingRows } from "@/components/states";
import { Button } from "@/components/ui/button";
import { api } from "@/lib/api";
import { deckDisplayName } from "@/lib/collections";
import { plural } from "@/lib/format";
import type { Stats } from "@/lib/types";
import { ActivityHeatmap } from "@/routes/stats/ActivityHeatmap";
import { CardStatesBar, CardStatesLegend, STATES } from "@/routes/stats/CardStatesBar";
import { percent, rememberedText } from "@/routes/stats/chart";
import { RetentionChart } from "@/routes/stats/RetentionChart";

function StatTile({ label, value, detail }: { label: string; value: string; detail: string }) {
  return (
    <div className="grid content-start gap-1 rounded-md border border-border bg-card p-4">
      <dt className="text-sm text-muted-foreground">{label}</dt>
      <dd className="text-2xl font-semibold tabular-nums">{value}</dd>
      <dd className="text-sm text-muted-foreground">{detail}</dd>
    </div>
  );
}

function Section({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: ReactNode;
}) {
  const id = `${title.toLowerCase().replace(/\s+/g, "-")}-heading`;
  return (
    <section aria-labelledby={id} className="grid min-w-0 gap-4">
      <div className="grid gap-1">
        <h2 id={id} className="text-lg font-semibold">
          {title}
        </h2>
        <p className="max-w-prose text-sm text-muted-foreground">{description}</p>
      </div>
      <div className="min-w-0 rounded-md border border-border bg-card p-4 sm:p-5">{children}</div>
    </section>
  );
}

function DeckTable({ decks }: { decks: Stats["decks"] }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[34rem] text-left text-sm tabular-nums">
        <thead>
          <tr className="border-b border-border text-muted-foreground">
            <th className="py-2 pr-3 font-medium">Deck</th>
            {STATES.map((state) => (
              <th key={state.key} className="px-3 py-2 text-right font-medium">
                {state.label}
              </th>
            ))}
            <th className="py-2 pl-3 text-right font-medium">Retention</th>
          </tr>
        </thead>
        <tbody>
          {decks.map((deck) => (
            <tr key={deck.deck_id} className="border-b border-border last:border-0">
              <td className="grid gap-1.5 py-2.5 pr-3">
                <Link to={`/decks/${deck.deck_id}`} className="font-medium hover:underline">
                  {deckDisplayName(deck.name)}
                </Link>
                <CardStatesBar states={deck.states} compact />
              </td>
              {STATES.map((state) => (
                <td key={state.key} className="px-3 py-2.5 text-right align-top">
                  {deck.states[state.key].toLocaleString()}
                </td>
              ))}
              <td
                className="py-2.5 pl-3 text-right align-top"
                title={deck.retention.reviews ? rememberedText(deck.retention) : undefined}
              >
                {percent(deck.retention)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function StatsPage() {
  const stats = useQuery({ queryKey: ["stats"], queryFn: () => api<Stats>("/me/stats") });

  return (
    <div className="grid gap-10">
      <title>Stats · Engram</title>
      <PageHeader
        title="Stats"
        description={
          <p className="text-muted-foreground">
            Your own studying. Days roll over at 4 a.m. in your timezone.
          </p>
        }
      />
      {stats.isPending ? (
        <LoadingRows rows={4} label="Loading your stats" />
      ) : stats.isError ? (
        <ErrorState error={stats.error} onRetry={() => void stats.refetch()} />
      ) : (
        <StatsContent stats={stats.data} />
      )}
    </div>
  );
}

function StatsContent({ stats }: { stats: Stats }) {
  const { activity, retention_last_30_days: recent } = stats;
  if (activity.total_reviews === 0 && stats.decks.length === 0) {
    return (
      <EmptyState title="Nothing to show yet">
        <p className="text-sm text-muted-foreground">
          Create or import a deck and study it; your activity shows up here.
        </p>
        <Button asChild size="sm">
          <Link to="/">Go to your decks</Link>
        </Button>
      </EmptyState>
    );
  }
  return (
    <>
      <dl className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatTile
          label="Current streak"
          value={plural(activity.current_streak, "day")}
          detail={activity.current_streak > 0 ? "Keep it going today" : "Study today to start one"}
        />
        <StatTile
          label="Longest streak"
          value={plural(activity.longest_streak, "day")}
          detail={`${plural(activity.days_studied, "day")} studied in all`}
        />
        <StatTile
          label="Reviews"
          value={activity.total_reviews.toLocaleString()}
          detail="All time"
        />
        <StatTile
          label="Retention"
          value={percent(recent)}
          detail={
            recent.reviews
              ? `Last 30 days · ${rememberedText(recent)}`
              : "Last 30 days · no reviews due"
          }
        />
      </dl>

      <Section title="Activity" description="Reviews per day over the past year.">
        {activity.total_reviews === 0 ? (
          <p className="text-sm text-muted-foreground">
            No reviews yet. Study a deck to fill this in.
          </p>
        ) : (
          <ActivityHeatmap activity={activity} />
        )}
      </Section>

      <Section
        title="Retention"
        description="Of the cards you reviewed on a later day than you last saw them, the share you didn't rate Again. Learning steps on the same day don't count."
      >
        <RetentionChart months={stats.retention_by_month} />
      </Section>

      <Section
        title="Cards"
        description="Where your cards stand, across the decks you can study. Young and mature split at a 21-day interval."
      >
        <div className="grid min-w-0 gap-6">
          <div className="grid gap-4">
            <CardStatesBar states={stats.states} />
            <CardStatesLegend states={stats.states} />
          </div>
          {stats.decks.length > 0 && <DeckTable decks={stats.decks} />}
        </div>
      </Section>
    </>
  );
}
