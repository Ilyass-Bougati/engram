import {
  ChartColumnIcon,
  ChevronDownIcon,
  CircleUserIcon,
  GalleryVerticalEndIcon,
  LogOutIcon,
  SettingsIcon,
  ShieldCheckIcon,
} from "lucide-react";
import type { ReactNode } from "react";
import { Link, NavLink, useLocation } from "react-router";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { EngramMark } from "@/components/EngramMark";
import { cn } from "@/lib/cn";
import { THEME_ICONS, THEME_OPTIONS, useThemePreference } from "@/lib/theme";

interface AppShellProps {
  username: string;
  isAdmin: boolean;
  onSignOut: () => void;
  children: ReactNode;
}

function navLinkClass({ isActive }: { isActive: boolean }): string {
  return cn(
    "inline-flex items-center gap-2 rounded-sm px-2.5 py-1.5 text-sm font-medium transition-colors duration-(--duration-fast) sm:px-3 [&_svg]:size-4 [&_svg]:shrink-0",
    isActive ? "bg-accent text-foreground" : "text-muted-foreground hover:text-foreground",
  );
}

// Below 640px the links show only their icons; the label stays for screen readers.
function NavLabel({ children }: { children: ReactNode }) {
  return <span className="max-sm:sr-only">{children}</span>;
}

export function AppShell({ username, isAdmin, onSignOut, children }: AppShellProps) {
  const { pathname } = useLocation();
  const onDecks = pathname === "/" || pathname.startsWith("/decks/");
  const [theme, setTheme] = useThemePreference();

  return (
    <div className="min-h-dvh">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 focus:rounded-sm focus:bg-card focus:px-3 focus:py-2 focus:text-sm"
      >
        Skip to content
      </a>
      <header className="glass sticky top-0 z-40 border-x-0! border-t-0!">
        <div className="mx-auto flex h-14 max-w-5xl items-center gap-2 px-4 sm:gap-6 sm:px-6">
          <Link
            to="/"
            className="mr-2 inline-flex items-center gap-2 text-base font-semibold tracking-tight"
          >
            <EngramMark className="size-6" />
            Engram
          </Link>
          <nav aria-label="Main">
            <ul className="flex items-center gap-1">
              <li>
                <NavLink
                  to="/"
                  className={() => navLinkClass({ isActive: onDecks })}
                  aria-current={onDecks ? "page" : undefined}
                >
                  <GalleryVerticalEndIcon aria-hidden />
                  <NavLabel>Decks</NavLabel>
                </NavLink>
              </li>
              <li>
                <NavLink to="/stats" className={navLinkClass}>
                  <ChartColumnIcon aria-hidden />
                  <NavLabel>Stats</NavLabel>
                </NavLink>
              </li>
              {isAdmin && (
                <li>
                  <NavLink to="/admin/invites" className={navLinkClass}>
                    <ShieldCheckIcon aria-hidden />
                    <NavLabel>Admin</NavLabel>
                  </NavLink>
                </li>
              )}
            </ul>
          </nav>
          <DropdownMenu>
            <DropdownMenuTrigger className="ml-auto inline-flex h-9 max-w-40 items-center gap-1.5 rounded-sm px-2 text-sm font-medium hover:bg-accent">
              <CircleUserIcon className="size-4 shrink-0 text-muted-foreground" aria-hidden />
              <span className="truncate">{username}</span>
              <ChevronDownIcon className="size-4 shrink-0 text-muted-foreground" aria-hidden />
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuLabel>Theme</DropdownMenuLabel>
              <DropdownMenuRadioGroup
                value={theme}
                onValueChange={(value) => {
                  const choice = THEME_OPTIONS.find((option) => option.value === value);
                  if (choice) setTheme(choice.value);
                }}
              >
                {THEME_OPTIONS.map((option) => {
                  const Icon = THEME_ICONS[option.value];
                  return (
                    <DropdownMenuRadioItem key={option.value} value={option.value}>
                      <Icon aria-hidden />
                      {option.label}
                    </DropdownMenuRadioItem>
                  );
                })}
              </DropdownMenuRadioGroup>
              <DropdownMenuSeparator />
              <DropdownMenuItem asChild>
                <Link to="/settings">
                  <SettingsIcon aria-hidden />
                  Settings
                </Link>
              </DropdownMenuItem>
              <DropdownMenuItem onSelect={onSignOut}>
                <LogOutIcon aria-hidden />
                Sign out
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </header>
      <main id="main" className="mx-auto max-w-5xl px-4 py-8 sm:px-6 sm:py-12">
        {/* Each page rises in when you navigate; changes within a page don't replay it. */}
        <div key={pathname} className="animate-rise-in">
          {children}
        </div>
      </main>
    </div>
  );
}
