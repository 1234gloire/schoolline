type FunctionErrorShape = {
  code?: string;
  message?: string;
  details?: unknown;
  customData?: {
    message?: string;
    details?: unknown;
  };
};

const GENERIC_MESSAGES = new Set([
  'internal',
  'error',
  'firebaseerror',
  'firebase error',
]);

export function getFirebaseFunctionErrorMessage(
  error: unknown,
  fallback: string
): string {
  const candidates = collectCandidates(error);

  for (const candidate of candidates) {
    const normalized = normalizeMessage(candidate);
    if (normalized) {
      return normalized;
    }
  }

  return fallback;
}

function collectCandidates(error: unknown): string[] {
  if (!error || typeof error !== 'object') {
    return [];
  }

  const value = error as FunctionErrorShape;

  return [
    readText(value.details),
    readText(value.customData?.details),
    readText(value.message),
    readText(value.customData?.message),
  ].filter((candidate): candidate is string => candidate.length > 0);
}

function readText(value: unknown): string {
  if (typeof value === 'string') {
    return value.trim();
  }

  if (value && typeof value === 'object') {
    const objectValue = value as Record<string, unknown>;
    if (typeof objectValue['message'] === 'string') {
      return objectValue['message'].trim();
    }
  }

  return '';
}

function normalizeMessage(message: string): string | null {
  const cleaned = message
    .trim()
    .replace(/^FirebaseError:\s*/i, '')
    .replace(/^functions\/[a-z-]+:\s*/i, '')
    .replace(/^Error:\s*/i, '')
    .trim();

  if (!cleaned) {
    return null;
  }

  if (GENERIC_MESSAGES.has(cleaned.toLowerCase())) {
    return null;
  }

  return cleaned;
}
