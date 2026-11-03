import { expect, importDeck, readStack, signInAs, test } from "../fixtures";

const SOLAR_SYSTEM = {
  format: "engram-deck",
  version: 1,
  deck: { name: "Solar system", description: "" },
  cards: [
    { type: "basic", front: "How many planets orbit the Sun?", back: "Eight", tags: [] },
    {
      type: "quiz",
      question: "Which planet is the largest?",
      options: [
        { text: "Jupiter", correct: true },
        { text: "Mars", correct: false },
        { text: "Venus", correct: false },
      ],
      explanation: "Jupiter's mass is more than twice that of all other planets combined.",
      tags: [],
    },
    {
      type: "quiz",
      question: "Which of these are gas giants?",
      select_all: true,
      options: [
        { text: "Saturn", correct: true },
        { text: "Earth", correct: false },
        { text: "Jupiter", correct: true },
        { text: "Mercury", correct: false },
      ],
      tags: [],
    },
  ],
};

const CORRECT: Record<string, string[]> = {
  "Which planet is the largest?": ["Jupiter"],
  "Which of these are gas giants?": ["Saturn", "Jupiter"],
};

test("a whole review session runs from the keyboard", async ({ page, apiAs }) => {
  const { student } = readStack().users;
  const deck = await importDeck(await apiAs(student), SOLAR_SYSTEM);
  await signInAs(page, student);
  await page.goto(`/decks/${deck.id}`);
  await page.getByRole("link", { name: "Study" }).click();

  const card = page.getByRole("article", { name: "Card" });
  const finished = page.getByRole("heading", { name: "Done for now" });
  const showAnswer = page.getByRole("button", { name: "Show answer" });
  const checkAnswer = page.getByRole("button", { name: "Check answer" });
  let answeredWrong = false;

  for (let step = 0; step < 10; step++) {
    await expect(finished.or(showAnswer).or(checkAnswer)).toBeVisible();
    if (await finished.isVisible()) break;

    if (await showAnswer.isVisible()) {
      await page.keyboard.press("Space");
      await expect(card.getByLabel("Answer")).toHaveText("Eight");
      // Easy, so the card graduates instead of coming back within the session.
      await page.keyboard.press("4");
      continue;
    }

    const question = (await card.locator(".markdown").first().innerText()).trim();
    const options = await card.locator("label").allInnerTexts();
    const correct = CORRECT[question] ?? [];
    // Get the single-answer question wrong once, to check that it's marked Again.
    const failNow = !answeredWrong && correct.length === 1;
    const picks = failNow
      ? options.filter((text) => !correct.some((c) => text.startsWith(c))).slice(0, 1)
      : correct;
    for (const pick of picks) {
      const index = options.findIndex((text) => text.startsWith(pick));
      await page.keyboard.press(String(index + 1));
    }
    await page.keyboard.press("Enter");

    if (failNow) {
      answeredWrong = true;
      await expect(card).toContainText("Not quite. This card is marked Again");
      await expect(card.getByText("Correct", { exact: true })).toHaveCount(1);
      await expect(card).toContainText("Jupiter's mass");
      await page.keyboard.press("Enter");
    } else {
      await expect(card).toContainText("Correct.");
      await page.keyboard.press("4");
    }
  }

  await expect(finished).toBeVisible();
  // Three cards, one of them failed and then answered again.
  await expect(page.getByText("You reviewed 4 cards.")).toBeVisible();
  expect(answeredWrong).toBe(true);
  await page.getByRole("link", { name: "Back to deck" }).click();
  await expect(page.getByText("Nothing due · 0 new · 3 cards")).toBeVisible();
});
