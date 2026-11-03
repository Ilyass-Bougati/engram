// Two stacked cards: the deck behind, the card you're on in front.
export function EngramMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden>
      <rect
        x="7.5"
        y="2.75"
        width="12.5"
        height="15.5"
        rx="2.5"
        transform="rotate(10 13.75 10.5)"
        className="fill-accent stroke-primary"
        strokeWidth="1.5"
      />
      <rect x="4" y="5.5" width="12.5" height="15.5" rx="2.5" className="fill-primary" />
    </svg>
  );
}
