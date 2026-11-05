import { ArrowRightIcon, SparklesIcon } from "lucide-react";
import { Link } from "react-router";

import { ShaderSwirl } from "@/components/ShaderSwirl";
import { deckDisplayName } from "@/lib/collections";
import { suggestDeck, suggestionReason } from "@/lib/suggestion";
import type { Deck } from "@/lib/types";

const SWIRL_TOKENS = ["--suggestion-1", "--suggestion-2", "--suggestion-3"];

// Nothing to study means no card: the deck list already shows that.
export function SuggestionCard({ decks }: { decks: Deck[] }) {
  const deck = suggestDeck(decks);
  if (!deck) return null;
  return (
    <Link
      to={`/decks/${deck.id}/study`}
      className="group relative isolate flex items-center gap-4 overflow-hidden rounded-lg bg-suggestion-2 p-5 text-on-suggestion sm:gap-6 sm:p-6"
    >
      <ShaderSwirl tokens={SWIRL_TOKENS} className="-z-10" />
      <span className="grid min-w-0 flex-1 gap-1">
        <span className="flex items-center gap-2 text-sm font-medium">
          <SparklesIcon className="size-4 shrink-0" aria-hidden />
          Suggested for you
        </span>
        <span className="line-clamp-2 text-xl font-semibold wrap-anywhere sm:text-2xl">
          {deckDisplayName(deck.name)}
        </span>
        <span className="tabular-nums">{suggestionReason(deck)}</span>
      </span>
      <span className="flex shrink-0 items-center gap-2 rounded-full bg-on-suggestion p-3 font-medium text-suggestion-2 sm:px-4 sm:py-2">
        <span className="max-sm:sr-only">Study now</span>
        <ArrowRightIcon
          className="size-5 transition-transform duration-(--duration-base) ease-standard group-hover:translate-x-1"
          aria-hidden
        />
      </span>
    </Link>
  );
}
