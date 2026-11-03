import { ChevronRightIcon } from "lucide-react";
import type { ReactNode } from "react";

import { AppShell } from "@/components/AppShell";
import { Button } from "@/components/ui/button";
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

// A reference page for reviewing the tokens and the shell in Phase 4. Served by the Vite dev
// server only (specimen.html is not a build input) and captured by e2e/specimen.spec.ts.

const TYPE_SCALE = [
  { className: "text-3xl font-semibold", spec: "36 / 600", sample: "Your decks" },
  { className: "text-2xl font-semibold", spec: "28 / 600", sample: "Linear algebra basics" },
  { className: "text-xl font-semibold", spec: "22 / 600", sample: "Cards" },
  { className: "text-lg font-medium", spec: "18 / 500", sample: "Share deck" },
  { className: "text-base", spec: "16 / 400", sample: "Cards you rate Easy come back later." },
  { className: "text-sm text-muted-foreground", spec: "14 / 400", sample: "3 due · 12 new" },
  {
    className: "text-xs font-medium text-muted-foreground",
    spec: "12 / 500",
    sample: "Updated today",
  },
];

const SWATCHES = [
  ["--paper-top", "Background"],
  ["--surface", "Surface"],
  ["--ink", "Text"],
  ["--ink-muted", "Secondary text"],
  ["--line-strong", "Control outline"],
  ["--pine", "Accent"],
  ["--pine-soft", "Selected"],
  ["--danger", "Danger"],
  ["--rating-again", "Again"],
  ["--rating-hard", "Hard"],
  ["--rating-good", "Good"],
  ["--rating-easy", "Easy"],
] as const;

const RATINGS = [
  { key: "1", label: "Again", color: "text-rating-again" },
  { key: "2", label: "Hard", color: "text-rating-hard" },
  { key: "3", label: "Good", color: "text-rating-good" },
  { key: "4", label: "Easy", color: "text-rating-easy" },
];

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="grid gap-6 border-t border-border pt-8">
      <h2 className="text-xl font-semibold">{title}</h2>
      {children}
    </section>
  );
}

export function Specimen() {
  return (
    <AppShell username="reader" isAdmin onSignOut={() => undefined}>
      <div className="grid gap-12">
        <header className="grid gap-2">
          <h1 className="text-3xl font-semibold">Design tokens</h1>
          <p className="max-w-prose text-muted-foreground">
            Everything on this page comes from src/styles/tokens.css. IBM Plex Sans for the
            interface and card text, <code className="text-sm">IBM Plex Mono</code> for code.
          </p>
        </header>

        <Section title="Type">
          <dl className="grid gap-4">
            {TYPE_SCALE.map((row) => (
              <div key={row.spec} className="grid gap-1 sm:grid-cols-[6rem_1fr] sm:items-baseline">
                <dt className="font-mono text-xs text-muted-foreground">{row.spec}</dt>
                <dd className={row.className}>{row.sample}</dd>
              </div>
            ))}
          </dl>
        </Section>

        <Section title="Color">
          <ul className="grid grid-cols-2 gap-x-6 gap-y-3 sm:grid-cols-3 lg:grid-cols-4">
            {SWATCHES.map(([token, name]) => (
              <li key={token} className="flex items-center gap-3">
                <span
                  className="size-8 shrink-0 rounded-sm border border-border"
                  style={{ backgroundColor: `var(${token})` }}
                />
                <span className="grid">
                  <span className="text-sm font-medium">{name}</span>
                  <span className="font-mono text-xs text-muted-foreground">{token}</span>
                </span>
              </li>
            ))}
          </ul>
        </Section>

        <Section title="Controls">
          <div className="flex flex-wrap gap-3">
            <Button>Study now</Button>
            <Button variant="secondary">Add card</Button>
            <Button variant="ghost">Cancel</Button>
            <Button variant="danger">Delete deck</Button>
            <Button disabled>Saving…</Button>
          </div>
          <div className="grid max-w-sm gap-6">
            <div className="grid gap-2">
              <Label htmlFor="specimen-name">Deck name</Label>
              <Input id="specimen-name" defaultValue="Linear algebra basics" />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="specimen-username">Username</Label>
              <Input
                id="specimen-username"
                defaultValue="nobody"
                aria-invalid
                aria-describedby="specimen-username-error"
              />
              <p id="specimen-username-error" className="text-sm text-destructive">
                No user named "nobody". Check the spelling.
              </p>
            </div>
          </div>
        </Section>

        <Section title="Surfaces">
          <div className="grid gap-3">
            <h3 className="text-sm font-medium text-muted-foreground">
              Solid: lists and everything else
            </h3>
            <ul className="divide-y divide-border rounded-md border border-border bg-card">
              {[
                ["Linear algebra basics", "3 due · 12 new"],
                ["Spanish verbs", "Nothing due · 20 new"],
              ].map(([name, counts]) => (
                <li key={name}>
                  <a href="#main" className="flex items-center gap-4 px-4 py-3 hover:bg-muted">
                    <span className="grid flex-1 gap-0.5">
                      <span className="font-medium">{name}</span>
                      <span className="text-sm text-muted-foreground tabular-nums">{counts}</span>
                    </span>
                    <ChevronRightIcon className="size-4 text-muted-foreground" aria-hidden />
                  </a>
                </li>
              ))}
            </ul>
          </div>

          <div className="grid gap-3">
            <h3 className="text-sm font-medium text-muted-foreground">
              Glass: the review card, the top bar, dialogs and menus
            </h3>
            <div className="py-6 sm:py-10">
              <article className="glass mx-auto grid w-full max-w-2xl gap-8 rounded-lg p-6 sm:p-10">
                <p className="text-review">
                  What is the determinant of a 2 × 2 matrix [[a, b], [c, d]]?
                </p>
                <div className="border-t border-border pt-6 text-review">ad − bc</div>
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                  {RATINGS.map((rating) => (
                    <Button
                      key={rating.key}
                      variant="secondary"
                      size="lg"
                      className="justify-between"
                    >
                      <span className={rating.color}>{rating.label}</span>
                      <kbd className="text-xs text-muted-foreground">{rating.key}</kbd>
                    </Button>
                  ))}
                </div>
              </article>
            </div>
          </div>
        </Section>

        <Section title="Dialog">
          <Dialog>
            <DialogTrigger asChild>
              <Button variant="secondary" className="justify-self-start">
                Share deck
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Share deck</DialogTitle>
                <DialogDescription>
                  They'll see every card in this deck. Their review progress stays their own.
                </DialogDescription>
              </DialogHeader>
              <div className="grid gap-4">
                <div className="grid gap-2">
                  <Label htmlFor="share-username">Username</Label>
                  <Input id="share-username" autoComplete="off" />
                </div>
                <div className="grid gap-2">
                  <Label htmlFor="share-role">Role</Label>
                  <select
                    id="share-role"
                    className="h-10 rounded-sm border border-input bg-card px-3 text-base"
                    defaultValue="viewer"
                  >
                    <option value="viewer">Viewer: can study</option>
                    <option value="editor">Editor: can study and edit cards</option>
                  </select>
                </div>
              </div>
              <DialogFooter>
                <DialogClose asChild>
                  <Button variant="ghost">Cancel</Button>
                </DialogClose>
                <Button>Share</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </Section>
      </div>
    </AppShell>
  );
}
