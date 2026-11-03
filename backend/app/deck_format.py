from typing import Annotated, Literal, Self

from pydantic import AfterValidator, Field, StringConstraints, model_validator

from app.schemas import StrictModel

MAX_TEXT_LENGTH = 20_000
MAX_CARDS_PER_FILE = 5_000

CardText = Annotated[str, StringConstraints(min_length=1, max_length=MAX_TEXT_LENGTH)]
OptionalCardText = Annotated[str, StringConstraints(max_length=MAX_TEXT_LENGTH)]
Tag = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True,
        to_lower=True,
        min_length=1,
        max_length=50,
        pattern=r"^[\w\-./:+#]+$",
    ),
]


def _unique(tags: list[str]) -> list[str]:
    return list(dict.fromkeys(tags))


Tags = Annotated[list[Tag], Field(max_length=20), AfterValidator(_unique)]


class QuizOptionData(StrictModel):
    text: CardText
    correct: bool


class BasicCardData(StrictModel):
    type: Literal["basic"]
    front: CardText
    back: CardText
    tags: Tags = Field(default_factory=list)


class QuizCardData(StrictModel):
    type: Literal["quiz"]
    question: CardText
    select_all: bool = False
    options: Annotated[list[QuizOptionData], Field(min_length=2, max_length=8)]
    explanation: OptionalCardText = ""
    tags: Tags = Field(default_factory=list)

    @model_validator(mode="after")
    def check_correct_options(self) -> Self:
        correct_count = sum(option.correct for option in self.options)
        if self.select_all and correct_count == 0:
            raise ValueError("a select-all quiz card needs at least one correct option")
        if not self.select_all and correct_count != 1:
            raise ValueError(
                f"a single-answer quiz card needs exactly one correct option (got {correct_count})"
            )
        return self


CardData = Annotated[BasicCardData | QuizCardData, Field(discriminator="type")]


class DeckMeta(StrictModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]
    description: Annotated[str, StringConstraints(max_length=2_000)] = ""


class DeckFile(StrictModel):
    format: Literal["engram-deck"]
    version: Literal[1]
    deck: DeckMeta
    cards: Annotated[list[CardData], Field(max_length=MAX_CARDS_PER_FILE)]
