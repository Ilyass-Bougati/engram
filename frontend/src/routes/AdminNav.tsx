import { LinkIcon, UsersIcon } from "lucide-react";
import { NavLink } from "react-router";

import { cn } from "@/lib/cn";

const LINKS = [
  { to: "/admin/invites", label: "Invites", icon: LinkIcon },
  { to: "/admin/users", label: "Users", icon: UsersIcon },
];

export function AdminNav() {
  return (
    <nav aria-label="Admin" className="border-b border-border">
      <ul className="-mb-px flex gap-6">
        {LINKS.map((link) => (
          <li key={link.to}>
            <NavLink
              to={link.to}
              className={({ isActive }) =>
                cn(
                  "inline-flex items-center gap-2 border-b-2 pb-3 text-sm font-medium transition-colors duration-(--duration-fast)",
                  isActive
                    ? "border-primary text-foreground"
                    : "border-transparent text-muted-foreground hover:text-foreground",
                )
              }
            >
              <link.icon className="size-4 shrink-0" aria-hidden />
              {link.label}
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  );
}
