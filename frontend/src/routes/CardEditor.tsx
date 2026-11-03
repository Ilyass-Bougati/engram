import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ArrowLeftIcon, CheckIcon, XIcon } from "lucide-react";
import { useRef, useState, type ReactNode } from "react";
import { Link, useNavigate, useParams } from "react-router";

import { DeckNotFound } from "@/components/DeckNotFound";
import { Markdown } from "@/components/markdown/Markdown";
import { ErrorState, FormError, LoadingRows } from "@/components/states";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { api, UserFacingError } from "@/lib/api";
import { parseTags } from "@/lib/form";
import { invalidateDeck, isNotFound, useDeck } from "@/lib/queries";
import type { Card, CardData, Deck } from "@/lib/types";

const MIN_OPTIONS = 2;
const MAX_OPTIONS = 8;

interface OptionDraft {
  key: string;
  text: string;
  correct: boolean;
}

interface Draft {
  type: "basic" | "quiz";
  front: string;
  back: string;
  question: string;
  selectAll: boolean;
  options: OptionDraft[];
  explanation: string;
  tags: string;
}

function blankOption(): OptionDraft {
  return { key: crypto.randomUUID(), text: "", correct: false };
}

function draftFrom(card: Card | undefined, type: Draft["type"] = "basic", tags = ""): Draft {
  const blank: Draft = {
    type,
    front: "",
    back: "",
    question: "",
    selectAll: false,
    options: [blankOption(), blankOption()],
    explanation: "",
    tags,
  };
  if (!card) return blank;
  if (card.type === "basic") {
    return {
      ...blank,
      type: "basic",
      front: card.front,
      back: card.back,
      tags: card.tags.join(" "),
    };
  }
  return {
    ...blank,
    type: "quiz",
    question: card.question,
    selectAll: card.select_all,
    options: card.options.map((option) => ({
      key: option.id,
      text: option.text,
      correct: option.correct ?? false,
    })),
    explanation: card.explanation ?? "",
    tags: card.tags.join(" "),
  };
}

function toCardData(draft: Draft): CardData {
  const tags = parseTags(draft.tags);
  if (draft.type === "basic") return { type: "basic", front: draft.front, back: draft.back, tags };
  return {
    type: "quiz",
    question: draft.question,
    select_all: draft.selectAll,
    options: draft.options.map(({ text, correct }) => ({ text, correct })),
    explanation: draft.explanation,
    tags,
  };
}

// The same rule the server enforces, checked first so the message can be specific.
function quizProblem(draft: Draft): string | null {
  if (draft.type !== "quiz") return null;
  const correct = draft.options.filter((option) => option.correct).length;
  if (draft.selectAll && correct === 0) return "Mark at least one option as correct.";
  if (!draft.selectAll && correct !== 1) return "Mark the one correct option.";
  return null;
}

function Preview({ draft }: { draft: Draft }) {
  const prompt = draft.type === "basic" ? draft.front : draft.question;
  return (
    <section aria-labelledby="preview-heading" className="grid content-start gap-3">
      <h2 id="preview-heading" className="text-sm font-medium text-muted-foreground">
        Preview
      </h2>
      <div className="grid gap-6 rounded-lg border border-border bg-card p-6 text-lg">
        {prompt.trim() ? (
          <Markdown>{prompt}</Markdown>
        ) : (
          <p className="text-muted-foreground">Nothing written yet.</p>
        )}
        {draft.type === "basic" ? (
          draft.back.trim() && (
            <div className="border-t border-border pt-6">
              <Markdown>{draft.back}</Markdown>
            </div>
          )
        ) : (
          <>
            <ul className="grid gap-2 text-base">
              {draft.options.map((option, index) => (
                <li
                  key={option.key}
                  className="flex items-start gap-3 rounded-sm border border-input px-3 py-2"
                >
                  <span className="font-mono text-xs leading-6 text-muted-foreground">
                    {index + 1}
                  </span>
                  <Markdown className="flex-1">{option.text || " "}</Markdown>
                  {option.correct && (
                    <span className="flex items-center gap-1 text-sm text-rating-good">
                      <CheckIcon className="size-4" aria-hidden />
                      Correct
                    </span>
                  )}
                </li>
              ))}
            </ul>
            {draft.explanation.trim() && (
              <div className="border-t border-border pt-6 text-base">
                <Markdown>{draft.explanation}</Markdown>
              </div>
            )}
          </>
        )}
      </div>
    </section>
  );
}

function Field({
  id,
  label,
  hint,
  children,
}: {
  id: string;
  label: string;
  hint?: string;
  children: ReactNode;
}) {
  return (
    <div className="grid gap-2">
      <Label htmlFor={id}>{label}</Label>
      {children}
      {hint && (
        <p id={`${id}-hint`} className="text-sm text-muted-foreground">
          {hint}
        </p>
      )}
    </div>
  );
}

function TypeChoice({
  value,
  onChange,
}: {
  value: Draft["type"];
  onChange: (type: Draft["type"]) => void;
}) {
  const choices = [
    { value: "basic", label: "Front and back" },
    { value: "quiz", label: "Multiple choice" },
  ] as const;
  return (
    <fieldset className="grid gap-2">
      <legend className="mb-2 text-sm font-medium">Card type</legend>
      <div className="flex flex-wrap gap-2">
        {choices.map((choice) => (
          <label
            key={choice.value}
            className="flex h-10 cursor-pointer items-center rounded-sm border border-input bg-card px-4 text-sm font-medium has-checked:border-primary has-checked:bg-accent has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-ring"
          >
            <input
              type="radio"
              name="card-type"
              value={choice.value}
              checked={value === choice.value}
              onChange={() => {
                onChange(choice.value);
              }}
              className="sr-only"
            />
            {choice.label}
          </label>
        ))}
      </div>
    </fieldset>
  );
}

function OptionsEditor({
  draft,
  update,
}: {
  draft: Draft;
  update: (patch: Partial<Draft>) => void;
}) {
  const setOption = (key: string, patch: Partial<OptionDraft>) => {
    update({
      options: draft.options.map((option) => {
        if (option.key === key) return { ...option, ...patch };
        // A single-answer card has one correct option: marking another clears the rest.
        if (patch.correct && !draft.selectAll) return { ...option, correct: false };
        return option;
      }),
    });
  };

  return (
    <fieldset className="grid gap-3">
      <legend className="mb-2 text-sm font-medium">Options</legend>
      <label className="flex items-center gap-2 text-sm">
        <Checkbox
          checked={draft.selectAll}
          onChange={(event) => {
            const selectAll = event.target.checked;
            // Back to single-answer: keep only the first correct option marked.
            const firstCorrect = draft.options.find((option) => option.correct)?.key;
            update({
              selectAll,
              options: selectAll
                ? draft.options
                : draft.options.map((option) => ({
                    ...option,
                    correct: option.key === firstCorrect,
                  })),
            });
          }}
        />
        Select all that apply (more than one option can be correct)
      </label>
      <ol className="grid gap-2">
        {draft.options.map((option, index) => {
          const number = index + 1;
          return (
            <li key={option.key} className="flex items-center gap-2">
              <Checkbox
                type={draft.selectAll ? "checkbox" : "radio"}
                name="correct-option"
                checked={option.correct}
                onChange={(event) => {
                  setOption(option.key, { correct: event.target.checked });
                }}
                aria-label={`Option ${String(number)} is correct`}
              />
              <Input
                aria-label={`Option ${String(number)}`}
                value={option.text}
                onChange={(event) => {
                  setOption(option.key, { text: event.target.value });
                }}
                required
                maxLength={20000}
                className="font-mono text-sm"
              />
              <Button
                type="button"
                variant="ghost"
                size="icon"
                disabled={draft.options.length <= MIN_OPTIONS}
                onClick={() => {
                  update({ options: draft.options.filter((other) => other.key !== option.key) });
                }}
                aria-label={`Remove option ${String(number)}`}
              >
                <XIcon aria-hidden />
              </Button>
            </li>
          );
        })}
      </ol>
      <div className="flex flex-wrap items-center gap-3">
        <Button
          type="button"
          variant="secondary"
          size="sm"
          disabled={draft.options.length >= MAX_OPTIONS}
          onClick={() => {
            update({ options: [...draft.options, blankOption()] });
          }}
        >
          Add option
        </Button>
        <p className="text-sm text-muted-foreground">
          {MIN_OPTIONS} to {MAX_OPTIONS} options. They're shuffled in every review.
        </p>
      </div>
    </fieldset>
  );
}

function DeleteCard({ deck, card }: { deck: Deck; card: Card }) {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const remove = useMutation({
    mutationFn: () => api(`/decks/${deck.id}/cards/${card.id}`, { method: "DELETE" }),
    onSuccess: () => {
      invalidateDeck(queryClient, deck.id);
      void navigate(`/decks/${deck.id}`);
    },
  });
  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button variant="ghost" className="text-destructive">
          Delete card
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Delete this card?</DialogTitle>
          <DialogDescription>
            It's removed for every member of the deck, with everyone's review history for it. It
            can't be undone.
          </DialogDescription>
        </DialogHeader>
        <FormError error={remove.error} />
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="ghost">Cancel</Button>
          </DialogClose>
          <Button
            variant="danger"
            disabled={remove.isPending}
            onClick={() => {
              remove.mutate();
            }}
          >
            {remove.isPending ? "Deleting…" : "Delete card"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function CardForm({ deck, card }: { deck: Deck; card: Card | undefined }) {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const firstField = useRef<HTMLTextAreaElement>(null);
  const [draft, setDraft] = useState(() => draftFrom(card));
  const [problem, setProblem] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const update = (patch: Partial<Draft>) => {
    setDraft((current) => ({ ...current, ...patch }));
    setProblem(null);
    setNotice(null);
  };

  const save = useMutation({
    mutationFn: ({ data }: { data: CardData; addAnother: boolean }) =>
      card
        ? api<Card>(`/decks/${deck.id}/cards/${card.id}`, { method: "PUT", body: data })
        : api<Card>(`/decks/${deck.id}/cards`, { method: "POST", body: data }),
    onSuccess: (saved, { addAnother }) => {
      invalidateDeck(queryClient, deck.id);
      queryClient.setQueryData(["card", deck.id, saved.id], saved);
      if (addAnother) {
        // Same type and tags: cards are usually added in runs of similar ones.
        setDraft((current) => draftFrom(undefined, current.type, current.tags));
        setNotice("Card added. Write the next one.");
        firstField.current?.focus();
      } else {
        void navigate(`/decks/${deck.id}`);
      }
    },
  });

  const submit = (addAnother: boolean) => {
    const quizError = quizProblem(draft);
    setProblem(quizError);
    if (!quizError) save.mutate({ data: toCardData(draft), addAnother });
  };

  const isNew = card === undefined;
  const formError = problem ? new UserFacingError(problem) : save.error;

  return (
    // On phones the preview sits between the fields and the buttons, so it's seen before saving.
    <div className="grid gap-8 lg:grid-cols-2 lg:items-start lg:gap-x-12">
      <form
        id="card-form"
        className="grid gap-6"
        onSubmit={(event) => {
          event.preventDefault();
          submit(false);
        }}
      >
        {isNew && (
          <TypeChoice
            value={draft.type}
            onChange={(type) => {
              update({ type });
            }}
          />
        )}
        {draft.type === "basic" ? (
          <>
            <Field id="card-front" label="Front">
              <Textarea
                ref={firstField}
                id="card-front"
                value={draft.front}
                onChange={(event) => {
                  update({ front: event.target.value });
                }}
                required
                maxLength={20000}
                autoFocus={isNew}
              />
            </Field>
            <Field id="card-back" label="Back">
              <Textarea
                id="card-back"
                value={draft.back}
                onChange={(event) => {
                  update({ back: event.target.value });
                }}
                required
                maxLength={20000}
              />
            </Field>
          </>
        ) : (
          <>
            <Field id="card-question" label="Question">
              <Textarea
                ref={firstField}
                id="card-question"
                value={draft.question}
                onChange={(event) => {
                  update({ question: event.target.value });
                }}
                required
                maxLength={20000}
              />
            </Field>
            <OptionsEditor draft={draft} update={update} />
            <Field
              id="card-explanation"
              label="Explanation (optional)"
              hint="Shown after answering, whether the answer was right or wrong."
            >
              <Textarea
                id="card-explanation"
                value={draft.explanation}
                onChange={(event) => {
                  update({ explanation: event.target.value });
                }}
                maxLength={20000}
                aria-describedby="card-explanation-hint"
              />
            </Field>
          </>
        )}
        <Field id="card-tags" label="Tags (optional)" hint="Separate tags with spaces or commas.">
          <Input
            id="card-tags"
            value={draft.tags}
            onChange={(event) => {
              update({ tags: event.target.value });
            }}
            aria-describedby="card-tags-hint"
            autoComplete="off"
          />
        </Field>
        <p className="text-sm text-muted-foreground">
          Text fields take Markdown, math between $ signs ($$ for a block), and fenced code blocks.
        </p>
        <FormError error={formError} />
        {notice && (
          <p role="status" className="text-sm text-muted-foreground">
            {notice}
          </p>
        )}
      </form>
      <div className="lg:sticky lg:top-24 lg:col-start-2 lg:row-span-2 lg:row-start-1">
        <Preview draft={draft} />
      </div>
      <div className="flex flex-wrap items-center gap-2 lg:col-start-1">
        <Button type="submit" form="card-form" disabled={save.isPending}>
          {save.isPending ? "Saving…" : isNew ? "Save card" : "Save changes"}
        </Button>
        {isNew && (
          <Button
            type="button"
            variant="secondary"
            disabled={save.isPending}
            onClick={() => {
              submit(true);
            }}
          >
            Save and add another
          </Button>
        )}
        <Button asChild variant="ghost">
          <Link to={`/decks/${deck.id}`}>Cancel</Link>
        </Button>
        {card && (
          <div className="ml-auto">
            <DeleteCard deck={deck} card={card} />
          </div>
        )}
      </div>
    </div>
  );
}

export function CardEditorPage() {
  const { deckId = "", cardId } = useParams();
  const deck = useDeck(deckId);
  const card = useQuery({
    queryKey: ["card", deckId, cardId],
    queryFn: () => api<Card>(`/decks/${deckId}/cards/${cardId ?? ""}`),
    enabled: cardId !== undefined,
  });

  const backLink = (
    <Link
      to={`/decks/${deckId}`}
      className="inline-flex items-center gap-1.5 justify-self-start text-sm text-muted-foreground hover:text-foreground"
    >
      <ArrowLeftIcon className="size-4" aria-hidden />
      {deck.data?.name ?? "Back to deck"}
    </Link>
  );

  if (deck.isPending || (cardId !== undefined && card.isPending)) {
    return <LoadingRows rows={2} label="Loading card" />;
  }
  if (deck.isError) {
    return isNotFound(deck.error) ? (
      <DeckNotFound />
    ) : (
      <ErrorState error={deck.error} onRetry={() => void deck.refetch()} />
    );
  }
  if (card.isError) {
    return isNotFound(card.error) ? (
      <div className="grid justify-items-start gap-4" role="alert">
        {backLink}
        <h1 className="text-2xl font-semibold">Card not found</h1>
        <p className="text-muted-foreground">
          It may have been deleted by another member of this deck.
        </p>
      </div>
    ) : (
      <ErrorState error={card.error} onRetry={() => void card.refetch()} />
    );
  }

  const title =
    cardId === undefined ? "New card" : deck.data.role === "viewer" ? "Card" : "Edit card";

  return (
    <div className="grid gap-8">
      <title>{`${title} · ${deck.data.name} · Engram`}</title>
      <div className="grid gap-3">
        {backLink}
        <h1 className="text-2xl font-semibold sm:text-3xl">{title}</h1>
      </div>
      {deck.data.role === "viewer" ? (
        card.data && (
          <div className="max-w-2xl">
            <Preview draft={draftFrom(card.data)} />
          </div>
        )
      ) : (
        <CardForm key={card.data?.id ?? "new"} deck={deck.data} card={card.data} />
      )}
    </div>
  );
}
