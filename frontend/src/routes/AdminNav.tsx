import { NavLink } from "react-router";

import { cn } from "@/lib/cn";

const LINKS = [
  { to: "/admin/invites", label: "Invites" },
  { to: "/admin/users", label: "Users" },
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
                  "inline-block border-b-2 pb-3 text-sm font-medium",
                  isActive
                    ? "border-primary text-foreground"
                    : "border-transparent text-muted-foreground hover:text-foreground",
                )
              }
            >
              {link.label}
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  );
}
