import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ArrowRightIcon, UploadIcon } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router";

import { FormError } from "@/components/states";
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
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { api } from "@/lib/api";
import { deckDisplayName } from "@/lib/collections";
import { plural } from "@/lib/format";
import type { AnkiImportResult } from "@/lib/types";

function ImportSummary({ result }: { result: AnkiImportResult }) {
  return (
    <div className="grid gap-2 text-sm" role="status">
      <p className="text-base">
        Imported {plural(result.imported, "card")} into{" "}
        <strong>{deckDisplayName(result.deck.name)}</strong>.
      </p>
      <ul className="grid list-disc gap-1 pl-5 text-muted-foreground">
        {result.reviews_imported > 0 && (
          <li>{plural(result.reviews_imported, "past review")} kept your schedule going.</li>
        )}
        {result.media_removed > 0 && (
          <li>
            {plural(result.media_removed, "card")} lost an image or a sound; Engram stores text
            only.
          </li>
        )}
        {result.skipped > 0 && (
          <li>
            {plural(result.skipped, "card")} {result.skipped === 1 ? "was" : "were"} left out: a
            side was empty without its image or sound, or longer than 20,000 characters.
          </li>
        )}
      </ul>
    </div>
  );
}

export function AnkiImportDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const queryClient = useQueryClient();
  const [step, setStep] = useState<"reading" | "uploading">("reading");
  const importPackage = useMutation({
    mutationFn: async ({ file, keepProgress }: { file: File; keepProgress: boolean }) => {
      setStep("reading");
      // Loaded on use, to keep the zip and zstd code out of the first download.
      const { extractAnkiCollection } = await import("@/lib/anki");
      const collection = await extractAnkiCollection(file);
      setStep("uploading");
      const params = new URLSearchParams({
        keep_progress: String(keepProgress),
        name: file.name.replace(/\.apkg$/i, "").slice(0, 200),
      });
      return api<AnkiImportResult>(`/decks/import/anki?${params.toString()}`, {
        method: "POST",
        body: collection,
      });
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["decks"] });
    },
  });
  const result = importPackage.data;

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        // Closing mid-import would hide the outcome; the import itself can't be cancelled.
        if (importPackage.isPending) return;
        if (!next) importPackage.reset();
        onOpenChange(next);
      }}
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Import from Anki</DialogTitle>
          <DialogDescription>
            In Anki, choose File → Export, then “Anki Deck Package (.apkg)”. Each Anki card becomes
            a front-and-back card here; images and sounds are left out.
          </DialogDescription>
        </DialogHeader>
        {result ? (
          <>
            <ImportSummary result={result} />
            <DialogFooter>
              <DialogClose asChild>
                <Button variant="ghost">Close</Button>
              </DialogClose>
              <Button asChild>
                <Link
                  to={`/decks/${result.deck.id}`}
                  onClick={() => {
                    onOpenChange(false);
                  }}
                >
                  Open deck
                  <ArrowRightIcon aria-hidden />
                </Link>
              </Button>
            </DialogFooter>
          </>
        ) : (
          <form
            className="grid gap-6"
            onSubmit={(event) => {
              event.preventDefault();
              const form = new FormData(event.currentTarget);
              const file = form.get("package");
              if (!(file instanceof File) || file.size === 0) return;
              importPackage.mutate({ file, keepProgress: form.get("keep-progress") === "on" });
            }}
          >
            <div className="grid gap-4">
              <div className="grid gap-2">
                <Label htmlFor="anki-package">Deck package</Label>
                <Input id="anki-package" name="package" type="file" accept=".apkg" required />
              </div>
              <div className="flex gap-3">
                <Checkbox
                  id="anki-keep-progress"
                  name="keep-progress"
                  defaultChecked
                  className="mt-1"
                  aria-describedby="anki-keep-progress-help"
                />
                <div className="grid gap-1">
                  <Label htmlFor="anki-keep-progress">Keep my Anki progress</Label>
                  <p id="anki-keep-progress-help" className="text-sm text-muted-foreground">
                    Cards you've studied keep their schedule and review history. It's yours only:
                    people you share the deck with start fresh.
                  </p>
                </div>
              </div>
            </div>
            <FormError error={importPackage.error} />
            <DialogFooter>
              <DialogClose asChild>
                <Button variant="ghost" disabled={importPackage.isPending}>
                  Cancel
                </Button>
              </DialogClose>
              <Button type="submit" disabled={importPackage.isPending}>
                <UploadIcon aria-hidden />
                {!importPackage.isPending
                  ? "Import"
                  : step === "reading"
                    ? "Reading package…"
                    : "Importing…"}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}
