export function CollectionHint({ id }: { id: string }) {
  return (
    <p id={id} className="text-sm text-muted-foreground">
      Use <code className="font-mono">::</code> to put the deck in a collection, as in{" "}
      <code className="font-mono whitespace-nowrap">Spanish::Verbs</code>.
    </p>
  );
}
