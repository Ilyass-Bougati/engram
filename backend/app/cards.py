import uuid
from collections import defaultdict
from collections.abc import Sequence

from sqlmodel import Session, col, delete, select

from app.deck_format import BasicCardData, CardData, QuizCardData, QuizOptionData
from app.models import Card, CardKind, CardTag, QuizOption, utcnow


def _apply_content(card: Card, data: CardData) -> tuple[list[QuizOption], list[CardTag]]:
    tags = [CardTag(card_id=card.id, tag=tag) for tag in data.tags]
    if isinstance(data, BasicCardData):
        card.kind = CardKind.basic
        card.prompt, card.answer = data.front, data.back
        card.explanation, card.select_all = None, False
        card.search_text = f"{data.front}\n{data.back}"
        return [], tags
    card.kind = CardKind.quiz
    card.prompt, card.answer = data.question, None
    card.explanation, card.select_all = data.explanation, data.select_all
    card.search_text = "\n".join([data.question, data.explanation, *(o.text for o in data.options)])
    options = [
        QuizOption(card_id=card.id, position=position, text=option.text, is_correct=option.correct)
        for position, option in enumerate(data.options)
    ]
    return options, tags


def add_cards(session: Session, deck_id: uuid.UUID, cards: Sequence[CardData]) -> list[Card]:
    # The deck row must already be flushed. Without ORM relationships SQLAlchemy doesn't order
    # inserts across tables, so cards are flushed before the options and tags pointing at them.
    new_cards: list[Card] = []
    children: list[QuizOption | CardTag] = []
    for data in cards:
        card = Card(deck_id=deck_id, kind=CardKind(data.type), prompt="", search_text="")
        options, tags = _apply_content(card, data)
        new_cards.append(card)
        children += [*options, *tags]
    session.add_all(new_cards)
    session.flush()
    session.add_all(children)
    return new_cards


def replace_card_content(session: Session, card: Card, data: CardData) -> None:
    session.exec(delete(QuizOption).where(col(QuizOption.card_id) == card.id))
    session.exec(delete(CardTag).where(col(CardTag.card_id) == card.id))
    options, tags = _apply_content(card, data)
    card.updated_at = utcnow()
    session.add(card)
    session.add_all([*options, *tags])


class CardDetails:
    # Options and tags for a batch of cards, loaded with two queries instead of two per card.
    def __init__(self, session: Session, card_ids: Sequence[uuid.UUID]) -> None:
        self.options: defaultdict[uuid.UUID, list[QuizOption]] = defaultdict(list)
        self.tags: defaultdict[uuid.UUID, list[str]] = defaultdict(list)
        if not card_ids:
            return
        for option in session.exec(
            select(QuizOption)
            .where(col(QuizOption.card_id).in_(card_ids))
            .order_by(col(QuizOption.position))
        ):
            self.options[option.card_id].append(option)
        for tag in session.exec(
            select(CardTag).where(col(CardTag.card_id).in_(card_ids)).order_by(col(CardTag.tag))
        ):
            self.tags[tag.card_id].append(tag.tag)

    def to_data(self, card: Card) -> CardData:
        if card.kind == CardKind.basic:
            return BasicCardData(
                type="basic", front=card.prompt, back=card.answer or "", tags=self.tags[card.id]
            )
        return QuizCardData(
            type="quiz",
            question=card.prompt,
            select_all=card.select_all,
            options=[
                QuizOptionData(text=option.text, correct=option.is_correct)
                for option in self.options[card.id]
            ],
            explanation=card.explanation or "",
            tags=self.tags[card.id],
        )
