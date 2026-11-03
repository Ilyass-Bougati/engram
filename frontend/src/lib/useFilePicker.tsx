import { useRef, type ReactElement } from "react";

// A hidden file input opened from any button or menu item, so the trigger can be styled freely.
export function useFilePicker(onFile: (file: File) => void): {
  open: () => void;
  input: ReactElement;
} {
  const ref = useRef<HTMLInputElement>(null);
  const input = (
    <input
      ref={ref}
      type="file"
      accept=".json,application/json"
      hidden
      onChange={(event) => {
        const file = event.target.files?.[0];
        // Cleared so picking the same file again (after fixing it) fires another change.
        event.target.value = "";
        if (file) onFile(file);
      }}
    />
  );
  return { open: () => ref.current?.click(), input };
}
