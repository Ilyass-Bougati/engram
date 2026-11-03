import { useMutation } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";

import { PageHeader } from "@/components/PageHeader";
import { FormError } from "@/components/states";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { api, UserFacingError } from "@/lib/api";
import { useAuth, useCurrentUser } from "@/lib/auth";
import { formText } from "@/lib/form";
import { THEME_OPTIONS, useThemePreference } from "@/lib/theme";
import type { SessionResponse, User } from "@/lib/types";

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
    <section
      aria-labelledby={id}
      className="grid gap-6 border-t border-border pt-8 md:grid-cols-[16rem_1fr] md:gap-12"
    >
      <div className="grid content-start gap-1">
        <h2 id={id} className="text-lg font-semibold">
          {title}
        </h2>
        <p className="text-sm text-muted-foreground">{description}</p>
      </div>
      <div className="max-w-md">{children}</div>
    </section>
  );
}

function ThemeSection() {
  const [theme, setTheme] = useThemePreference();
  return (
    <Section title="Theme" description="Saved in this browser.">
      <fieldset className="grid gap-3">
        <legend className="sr-only">Theme</legend>
        {THEME_OPTIONS.map((option) => (
          <label key={option.value} className="flex items-center gap-3 text-base">
            <input
              type="radio"
              name="theme"
              className="size-4 accent-primary"
              checked={theme === option.value}
              onChange={() => {
                setTheme(option.value);
              }}
            />
            {option.label}
          </label>
        ))}
      </fieldset>
    </Section>
  );
}

function timezones(current: string): string[] {
  const names = Intl.supportedValuesOf("timeZone");
  return names.includes(current) ? names : [current, ...names];
}

function TimezoneSection() {
  const user = useCurrentUser();
  const { updateUser } = useAuth();
  const [timezone, setTimezone] = useState(user.timezone);
  const [saved, setSaved] = useState(false);
  const save = useMutation({
    mutationFn: () => api<User>("/me", { method: "PATCH", body: { timezone } }),
    onSuccess: (updated) => {
      updateUser(updated);
      setSaved(true);
    },
  });
  const detected = Intl.DateTimeFormat().resolvedOptions().timeZone;

  return (
    <Section
      title="Timezone"
      description="Your study day starts at 4:00 here: that's when new cards unlock."
    >
      <form
        className="grid gap-4"
        onSubmit={(event) => {
          event.preventDefault();
          save.mutate();
        }}
      >
        <div className="grid gap-2">
          <Label htmlFor="timezone">Timezone</Label>
          <Select
            id="timezone"
            value={timezone}
            onChange={(event) => {
              setTimezone(event.target.value);
              setSaved(false);
            }}
          >
            {timezones(timezone).map((name) => (
              <option key={name} value={name}>
                {name.replaceAll("_", " ")}
              </option>
            ))}
          </Select>
          {detected !== timezone && (
            <p className="text-sm text-muted-foreground">
              This browser is set to {detected.replaceAll("_", " ")}.{" "}
              <button
                type="button"
                className="font-medium text-foreground underline underline-offset-2"
                onClick={() => {
                  setTimezone(detected);
                  setSaved(false);
                }}
              >
                Use it
              </button>
            </p>
          )}
        </div>
        <FormError error={save.error} />
        {saved && (
          <p role="status" className="text-sm text-muted-foreground">
            Timezone saved.
          </p>
        )}
        <Button
          type="submit"
          variant="secondary"
          className="justify-self-start"
          disabled={save.isPending || timezone === user.timezone}
        >
          {save.isPending ? "Saving…" : "Save timezone"}
        </Button>
      </form>
    </Section>
  );
}

function PasswordSection() {
  const { startSession } = useAuth();
  const [mismatch, setMismatch] = useState(false);
  const [changed, setChanged] = useState(false);
  const change = useMutation({
    mutationFn: (body: { current_password: string; new_password: string }) =>
      api<SessionResponse>("/me/password", { method: "POST", body }),
    onSuccess: (session) => {
      startSession(session);
      setChanged(true);
    },
  });
  const formError = mismatch
    ? new UserFacingError("The new passwords don't match. Type the same password in both fields.")
    : change.error;

  return (
    <Section
      title="Password"
      description="Changing it signs you out on every other device and browser."
    >
      <form
        className="grid gap-4"
        onSubmit={(event) => {
          event.preventDefault();
          const form = event.currentTarget;
          const data = new FormData(form);
          const password = formText(data, "new-password");
          const matches = password === formText(data, "confirm-password");
          setMismatch(!matches);
          setChanged(false);
          if (!matches) return;
          change.mutate(
            { current_password: formText(data, "current-password"), new_password: password },
            {
              onSuccess: () => {
                form.reset();
              },
            },
          );
        }}
      >
        <div className="grid gap-2">
          <Label htmlFor="current-password">Current password</Label>
          <Input
            id="current-password"
            name="current-password"
            type="password"
            autoComplete="current-password"
            required
          />
        </div>
        <div className="grid gap-2">
          <Label htmlFor="new-password">New password</Label>
          <Input
            id="new-password"
            name="new-password"
            type="password"
            autoComplete="new-password"
            required
            minLength={10}
            maxLength={256}
            aria-describedby="new-password-hint"
          />
          <p id="new-password-hint" className="text-sm text-muted-foreground">
            At least 10 characters.
          </p>
        </div>
        <div className="grid gap-2">
          <Label htmlFor="confirm-password">Confirm new password</Label>
          <Input
            id="confirm-password"
            name="confirm-password"
            type="password"
            autoComplete="new-password"
            required
            aria-invalid={mismatch || undefined}
          />
        </div>
        <FormError error={formError} />
        {changed && (
          <p role="status" className="text-sm text-muted-foreground">
            Password changed. Other sessions have been signed out.
          </p>
        )}
        <Button
          type="submit"
          variant="secondary"
          className="justify-self-start"
          disabled={change.isPending}
        >
          {change.isPending ? "Changing…" : "Change password"}
        </Button>
      </form>
    </Section>
  );
}

export function SettingsPage() {
  const user = useCurrentUser();
  return (
    <div className="grid gap-8">
      <title>Settings · Engram</title>
      <PageHeader
        title="Settings"
        description={<p className="text-muted-foreground">Signed in as {user.username}.</p>}
      />
      <div className="grid gap-12">
        <ThemeSection />
        <TimezoneSection />
        <PasswordSection />
      </div>
    </div>
  );
}
