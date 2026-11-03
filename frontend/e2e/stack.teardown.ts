import { rmSync } from "node:fs";

import { test as teardown } from "@playwright/test";

import { compose, STACK_FILE } from "./stack";

teardown("remove the throwaway stack and its database", () => {
  teardown.setTimeout(120_000);
  // `down` doesn't read the secrets, but compose still requires them to be set.
  compose(["down", "--volumes", "--remove-orphans"], {
    POSTGRES_PASSWORD: "unused",
    JWT_SECRET: "unused",
  });
  rmSync(STACK_FILE, { force: true });
});
