import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeftIcon,
  ArrowRightIcon,
  CalendarClockIcon,
  CheckIcon,
  CircleCheckBigIcon,
  CircleCheckIcon,
  CircleXIcon,
  EyeIcon,
  XIcon,
} from "lucide-react";
import { useEffect, useEffectEvent, useRef, useState, type ReactNode } from "react";
import { Link, useParams } from "react-router";

import { DeckNotFound } from "@/components/DeckNotFound";
import { Markdown } from "@/components/markdown/Markdown";
import { ErrorState, FormError } from "@/components/states";
import { Button } from "@/components/ui/button";
import { api } from "@/lib/api";
import { cn } from "@/lib/cn";
import { deckDisplayName } from "@/lib/collections";
import { formatRelative, plural, studyCountsText } from "@/lib/format";
import { isNotFound, useDeck } from "@/lib/queries";
import type { Deck, QuizResult, StudyCard, StudyNext } from "@/lib/types";

type QuizCard = Extract<StudyCard, { type: "quiz" }>;
type BasicCard = Extract<StudyCard, { type: "basic" }>;

const RATINGS = [
  { value: 1, label: "Again", className: "text-rating-again" },
  { value: 2, label: "Hard", className: "text-rating-hard" },
  { value: 3, label: "Good", className: "text-rating-good" },
  { value: 4, label: "Easy", className: "text-rating-easy" },
] as const;

type Rating = (typeof RATINGS)[number]["value"];

function isTyping(target: EventTarget | null): boolean {
  return (
    target instanceof HTMLElement &&
    (target.isContentEditable ||
      target.closest("textarea, select, input:not([type=radio], [type=checkbox])") !== null)
  );
}

// Window-level shortcuts. Space and Enter on a focused control are left to the browser, which
// already activates it; handling them here too would act twice.
function useShortcuts(onKey: (key: string) => boolean) {
  const handle = useEffectEvent(onKey);
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.altKey || event.ctrlKey || event.metaKey || event.repeat || isTyping(event.target))
        return;
      const onControl =
        event.target instanceof HTMLElement && event.target.closest("button, a") !== null;
      if ((event.key === " " || event.key === "Enter") && onControl) return;
      if (event.key === " " && event.target instanceof HTMLInputElement) return;
      if (handle(event.key)) event.preventDefault();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => {
      window.removeEventListener("keydown", onKeyDown);
    };
  }, []);
}

function Kbd({ children }: { children: ReactNode }) {
  return <kbd className="font-mono text-xs text-muted-foreground">{children}</kbd>;
}

function RatingButtons({
  ratings,
  disabled,
  onRate,
}: {
  ratings: readonly Rating[];
  disabled: boolean;
  onRate: (rating: Rating) => void;
}) {
  return (
    <div
      role="group"
      aria-label="How well did you remember it?"
      className={cn(
        "grid gap-2",
        ratings.length === 4 ? "grid-cols-2 sm:grid-cols-4" : "grid-cols-3",
      )}
    >
      {RATINGS.filter((rating) => ratings.includes(rating.value)).map((rating) => (
        <Button
          key={rating.value}
          variant="secondary"
          size="lg"
          className="justify-between"
          disabled={disabled}
          onClick={() => {
            onRate(rating.value);
          }}
          aria-keyshortcuts={String(rating.value)}
        >
          <span className={rating.className}>{rating.label}</span>
          <Kbd>{rating.value}</Kbd>
        </Button>
      ))}
    </div>
  );
}

interface ReviewProps<Card> {
  card: Card;
  deckId: string;
  rate: (rating: Rating) => void;
  rating: { isPending: boolean; error: unknown };
  advance: (next: StudyNext) => void;
}

function BasicReview({ card, rate, rating }: ReviewProps<BasicCard>) {
  const [revealed, setRevealed] = useState(false);
  const answer = useRef<HTMLDivElement>(null);

  const reveal = () => {
    setRevealed(true);
    // Focus moves to the answer, not a rating button, so a second Space can't rate by accident.
    requestAnimationFrame(() => answer.current?.focus());
  };

  useShortcuts((key) => {
    if (!revealed && (key === " " || key === "Enter")) {
      reveal();
      return true;
    }
    if (revealed && !rating.isPending && ["1", "2", "3", "4"].includes(key)) {
      rate(Number(key) as Rating);
      return true;
    }
    return false;
  });

  return (
    <>
      <Markdown className="text-review">{card.front}</Markdown>
      {revealed ? (
        <>
          <div
            ref={answer}
            tabIndex={-1}
            aria-label="Answer"
            className="animate-rise-in border-t border-border pt-8 outline-none"
          >
            <Markdown className="text-review">{card.back}</Markdown>
          </div>
          <div className="grid animate-rise-in gap-3">
            <RatingButtons ratings={[1, 2, 3, 4]} disabled={rating.isPending} onRate={rate} />
            <FormError error={rating.error} />
          </div>
        </>
      ) : (
        <Button
          size="lg"
          variant="secondary"
          className="justify-between"
          onClick={reveal}
          aria-keyshortcuts="Space"
        >
          <span className="inline-flex items-center gap-2">
            <EyeIcon aria-hidden />
            Show answer
          </span>
          <Kbd>Space</Kbd>
        </Button>
      )}
    </>
  );
}

function QuizReview({ card, deckId, rate, rating, advance }: ReviewProps<QuizCard>) {
  const [selected, setSelected] = useState<string[]>([]);
  const [result, setResult] = useState<QuizResult | null>(null);
  const resultRef = useRef<HTMLDivElement>(null);
  const answer = useMutation({
    mutationFn: () =>
      api<QuizResult>(`/decks/${deckId}/reviews/quiz-answer`, {
        method: "POST",
        body: { card_id: card.id, selected_option_ids: selected },
      }),
    onSuccess: (quizResult) => {
      setResult(quizResult);
      requestAnimationFrame(() => resultRef.current?.focus());
    },
  });

  const toggle = (optionId: string) => {
    setSelected((current) => {
      if (!card.select_all) return [optionId];
      return current.includes(optionId)
        ? current.filter((id) => id !== optionId)
        : [...current, optionId];
    });
  };
  const submit = () => {
    if (selected.length > 0 && !answer.isPending) answer.mutate();
  };
  const next = result?.next ?? null;

  useShortcuts((key) => {
    if (result === null) {
      const option = /^[1-8]$/.test(key) ? card.options[Number(key) - 1] : undefined;
      if (option) {
        toggle(option.id);
        return true;
      }
      if (key === "Enter") {
        submit();
        return true;
      }
      return false;
    }
    if (next && (key === "Enter" || key === " ")) {
      advance(next);
      return true;
    }
    if (result.correct && !rating.isPending && ["2", "3", "4"].includes(key)) {
      rate(Number(key) as Rating);
      return true;
    }
    return false;
  });

  return (
    <>
      <Markdown className="text-review">{card.question}</Markdown>
      <fieldset className="grid gap-2" disabled={result !== null || answer.isPending}>
        <legend className="sr-only">
          {card.select_all ? "Select all that apply" : "Choose one answer"}
        </legend>
        {card.select_all && (
          <p className="text-sm text-muted-foreground" aria-hidden>
            Select all that apply
          </p>
        )}
        {card.options.map((option, index) => {
          const isSelected = selected.includes(option.id);
          const isCorrect = result?.correct_option_ids.includes(option.id) ?? false;
          const isWrongPick = result !== null && isSelected && !isCorrect;
          return (
            <label
              key={option.id}
              className={cn(
                "flex cursor-pointer items-start gap-3 rounded-sm border border-input bg-card px-4 py-3 has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-ring",
                result === null && isSelected && "border-primary bg-accent",
                isCorrect && "border-rating-good",
                isWrongPick && "border-destructive",
                result !== null && "cursor-default",
              )}
            >
              <input
                type={card.select_all ? "checkbox" : "radio"}
                name="quiz-option"
                className="mt-1 size-4 shrink-0 accent-primary"
                checked={isSelected}
                onChange={() => {
                  toggle(option.id);
                }}
              />
              <Markdown className="flex-1">{option.text}</Markdown>
              {isCorrect ? (
                <span className="flex shrink-0 items-center gap-1 text-sm font-medium text-rating-good">
                  <CheckIcon className="size-4" aria-hidden />
                  Correct
                </span>
              ) : isWrongPick ? (
                <span className="flex shrink-0 items-center gap-1 text-sm font-medium text-destructive">
                  <XIcon className="size-4" aria-hidden />
                  Your answer
                </span>
              ) : (
                result === null && <Kbd>{index + 1}</Kbd>
              )}
            </label>
          );
        })}
      </fieldset>
      {result === null ? (
        <div className="grid gap-3">
          <Button
            size="lg"
            className="justify-between"
            disabled={selected.length === 0 || answer.isPending}
            onClick={submit}
            aria-keyshortcuts="Enter"
          >
            <span className="inline-flex items-center gap-2">
              <CheckIcon aria-hidden />
              {answer.isPending ? "Checking…" : "Check answer"}
            </span>
            <kbd className="font-mono text-xs">Enter</kbd>
          </Button>
          <FormError error={answer.error} />
        </div>
      ) : (
        <div ref={resultRef} tabIndex={-1} className="grid animate-rise-in gap-6 outline-none">
          <div className="grid gap-3 border-t border-border pt-6">
            <p
              className={cn(
                "flex items-start gap-2 font-semibold",
                result.correct ? "text-rating-good" : "text-destructive",
              )}
            >
              {result.correct ? (
                <CircleCheckIcon className="mt-0.5 size-5 shrink-0" aria-hidden />
              ) : (
                <CircleXIcon className="mt-0.5 size-5 shrink-0" aria-hidden />
              )}
              {result.correct
                ? "Correct."
                : "Not quite. This card is marked Again and comes back soon."}
            </p>
            {result.explanation.trim() && <Markdown>{result.explanation}</Markdown>}
          </div>
          {next ? (
            <Button
              size="lg"
              variant="secondary"
              className="justify-between"
              onClick={() => {
                advance(next);
              }}
            >
              <span className="inline-flex items-center gap-2">
                Next card
                <ArrowRightIcon aria-hidden />
              </span>
              <Kbd>Enter</Kbd>
            </Button>
          ) : (
            <div className="grid gap-3">
              <RatingButtons ratings={[2, 3, 4]} disabled={rating.isPending} onRate={rate} />
              <FormError error={rating.error} />
            </div>
          )}
        </div>
      )}
    </>
  );
}

function Finished({ deck, study, reviewed }: { deck: Deck; study: StudyNext; reviewed: number }) {
  let detail: string;
  if (study.next_due_at) {
    detail = `The next review is due ${formatRelative(study.next_due_at)}.`;
  } else if (deck.card_count === 0) {
    detail = "This deck has no cards yet.";
  } else {
    detail = `You've had today's ${plural(deck.new_cards_per_day, "new card")}. More come after 4:00 tomorrow, or raise the limit in deck settings.`;
  }
  return (
    <div className="grid animate-rise-in justify-items-start gap-6">
      <span className="grid size-12 place-items-center rounded-full bg-accent text-primary">
        {reviewed > 0 ? (
          <CircleCheckBigIcon className="size-6" aria-hidden />
        ) : (
          <CalendarClockIcon className="size-6" aria-hidden />
        )}
      </span>
      <div className="grid gap-2">
        <h1 className="text-2xl font-semibold">
          {reviewed > 0 ? "Done for now" : "Nothing to study right now"}
        </h1>
        <p className="text-muted-foreground">
          {reviewed > 0 && `You reviewed ${plural(reviewed, "card")}. `}
          {detail}
        </p>
      </div>
      <Button asChild>
        <Link to={`/decks/${deck.id}`}>
          <ArrowLeftIcon aria-hidden />
          Back to deck
        </Link>
      </Button>
    </div>
  );
}

function StudySession({ deck }: { deck: Deck }) {
  const queryClient = useQueryClient();
  const [current, setCurrent] = useState<StudyNext | null>(null);
  const [reviewed, setReviewed] = useState(0);
  const cardRef = useRef<HTMLElement>(null);
  const initial = useQuery({
    queryKey: ["study", deck.id],
    queryFn: () => api<StudyNext>(`/decks/${deck.id}/study/next`),
    staleTime: 0,
    gcTime: 0,
  });

  // Counts on the deck pages are stale once anything is rated here.
  useEffect(
    () => () => {
      void queryClient.invalidateQueries({ queryKey: ["decks"] });
      void queryClient.invalidateQueries({ queryKey: ["deck", deck.id] });
    },
    [queryClient, deck.id],
  );

  const advance = (next: StudyNext) => {
    setCurrent(next);
    setReviewed((count) => count + 1);
    // Screen readers start reading the new card; the old focus target is gone.
    requestAnimationFrame(() => cardRef.current?.focus());
  };
  const rating = useMutation({
    mutationFn: ({ cardId, value }: { cardId: string; value: Rating }) =>
      api<StudyNext>(`/decks/${deck.id}/reviews`, {
        method: "POST",
        body: { card_id: cardId, rating: value },
      }),
    onSuccess: advance,
  });

  const study = current ?? initial.data;
  const counts = study && (
    <p className="text-sm text-muted-foreground tabular-nums" aria-live="polite">
      {studyCountsText(study.due_count, study.new_count)}
    </p>
  );

  let body: ReactNode;
  let bodyKey = "loading";
  if (initial.isPending) {
    body = (
      <div role="status" aria-label="Loading the next card" className="grid gap-4">
        <div className="h-7 w-3/4 rounded-sm bg-muted" />
        <div className="h-7 w-1/2 rounded-sm bg-muted" />
      </div>
    );
  } else if (initial.isError) {
    bodyKey = "error";
    body = <ErrorState error={initial.error} onRetry={() => void initial.refetch()} />;
  } else if (study?.card) {
    const props = {
      deckId: deck.id,
      rate: (value: Rating) => {
        if (study.card) rating.mutate({ cardId: study.card.id, value });
      },
      rating: { isPending: rating.isPending, error: rating.error },
      advance,
    };
    // Keyed per review, not per card: a card failed moments ago can come straight back.
    bodyKey = `${study.card.id}-${String(reviewed)}`;
    body =
      study.card.type === "basic" ? (
        <BasicReview card={study.card} {...props} />
      ) : (
        <QuizReview card={study.card} {...props} />
      );
  }

  return (
    <>
      <header className="mx-auto flex w-[calc(100%-2rem)] max-w-2xl items-center justify-between gap-4 py-4 sm:w-[calc(100%-3rem)]">
        <Link
          to={`/decks/${deck.id}`}
          className="inline-flex min-w-0 items-center gap-1.5 text-sm text-muted-foreground transition-colors duration-(--duration-fast) hover:text-foreground"
        >
          <ArrowLeftIcon className="size-4 shrink-0" aria-hidden />
          <span className="truncate">{deckDisplayName(deck.name)}</span>
        </Link>
        {study?.card && counts}
      </header>
      <main className="flex flex-1 justify-center px-4 pt-[min(8vh,4rem)] pb-16 sm:px-6">
        {study && !study.card ? (
          <div className="w-full max-w-2xl">
            <Finished deck={deck} study={study} reviewed={reviewed} />
          </div>
        ) : (
          <article
            ref={cardRef}
            tabIndex={-1}
            aria-label="Card"
            className="glass-thin h-fit w-full max-w-2xl rounded-lg p-6 outline-none sm:p-10"
          >
            {/* Each card rises in; the glass around it stays put. */}
            <div key={bodyKey} className="grid animate-rise-in gap-8">
              {body}
            </div>
          </article>
        )}
      </main>
    </>
  );
}

export function StudyPage() {
  const { deckId = "" } = useParams();
  const deck = useDeck(deckId);
  useEffect(() => {
    const root = document.documentElement;
    root.dataset.scene = "study";
    return () => {
      delete root.dataset.scene;
    };
  }, []);
  return (
    <div className="flex min-h-dvh flex-col">
      <title>{`Study${deck.data ? ` · ${deckDisplayName(deck.data.name)}` : ""} · Engram`}</title>
      {deck.isPending ? (
        <p role="status" className="sr-only">
          Loading
        </p>
      ) : deck.isError ? (
        <main className="mx-auto w-full max-w-2xl px-4 py-12">
          {isNotFound(deck.error) ? (
            <DeckNotFound />
          ) : (
            <ErrorState error={deck.error} onRetry={() => void deck.refetch()} />
          )}
        </main>
      ) : (
        <StudySession deck={deck.data} />
      )}
    </div>
  );
}
