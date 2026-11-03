import { RotateCwIcon } from "lucide-react";

import { CenteredPage } from "@/components/CenteredPage";
import { Button } from "@/components/ui/button";

// Last resort for a rendering error: say so plainly and offer the one fix that usually works.
export function RouteError() {
  return (
    <CenteredPage>
      <div className="grid gap-2" role="alert">
        <h1 className="text-2xl font-semibold">Something went wrong</h1>
        <p className="text-muted-foreground">
          This page hit an error. Reload to try again; your progress is saved on the server.
        </p>
      </div>
      <Button
        className="self-start"
        onClick={() => {
          window.location.reload();
        }}
      >
        <RotateCwIcon aria-hidden />
        Reload
      </Button>
    </CenteredPage>
  );
}
