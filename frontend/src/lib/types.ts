// Response and request shapes of the backend API (backend/app/routers). Kept by hand: the API
// is small and the backend serves no OpenAPI document to generate from.

export type GlobalRole = "admin" | "user";
export type DeckRole = "owner" | "editor" | "viewer";

export interface User {
  id: string;
  username: string;
  role: GlobalRole;
  timezone: string;
  created_at: string;
}

export interface SessionResponse {
  access_token: string;
  user: User;
}

export interface Deck {
  id: string;
  name: string;
  description: string;
  role: DeckRole;
  card_count: number;
  due_count: number;
  new_count: number;
  new_cards_per_day: number;
  created_at: string;
  updated_at: string;
}

export interface QuizOption {
  id: string;
  text: string;
  // Present for editors and owners only.
  correct?: boolean;
}

export interface BasicCard {
  id: string;
  type: "basic";
  front: string;
  back: string;
  tags: string[];
  created_at: string;
  updated_at: string;
}

export interface QuizCard {
  id: string;
  type: "quiz";
  question: string;
  select_all: boolean;
  options: QuizOption[];
  explanation: string | null;
  tags: string[];
  created_at: string;
  updated_at: string;
}

export type Card = BasicCard | QuizCard;

export interface CardPage {
  cards: Card[];
  next_cursor: string | null;
}

export interface TagCount {
  tag: string;
  card_count: number;
}

export interface Member {
  user_id: string;
  username: string;
  role: DeckRole;
}

// The card body accepted by POST/PUT .../cards and by deck files (docs/deck-format.md).
export type CardData =
  | { type: "basic"; front: string; back: string; tags: string[] }
  | {
      type: "quiz";
      question: string;
      select_all: boolean;
      options: { text: string; correct: boolean }[];
      explanation: string;
      tags: string[];
    };

export type StudyCard =
  | { id: string; type: "basic"; front: string; back: string }
  | {
      id: string;
      type: "quiz";
      question: string;
      select_all: boolean;
      options: { id: string; text: string }[];
    };

export interface StudyNext {
  card: StudyCard | null;
  due_count: number;
  new_count: number;
  next_due_at: string | null;
}

export interface QuizResult {
  correct: boolean;
  correct_option_ids: string[];
  explanation: string;
  next: StudyNext | null;
}

export type InviteState = "pending" | "used" | "expired" | "revoked";

export interface InviteSummary {
  id: string;
  state: InviteState;
  created_at: string;
  expires_at: string;
  created_by: string;
  used_by: string | null;
  used_at: string | null;
}

export interface CreatedInvite {
  invite: InviteSummary;
  token: string;
}

export interface AdminUser {
  id: string;
  username: string;
  role: GlobalRole;
  is_active: boolean;
  created_at: string;
}
