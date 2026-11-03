import { apiResponse } from "@/lib/api";

// Export needs the bearer token, so a plain <a href> can't fetch it; save the response instead.
export async function downloadFromApi(path: string, fallbackName: string): Promise<void> {
  const response = await apiResponse(path);
  const disposition = response.headers.get("Content-Disposition") ?? "";
  const filename = /filename="([^"]+)"/.exec(disposition)?.[1] ?? fallbackName;
  const url = URL.createObjectURL(await response.blob());
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}
