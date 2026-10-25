---
name: unslop-ai-codebase
description: Edit codebase text, documentation, and comments to remove AI-generated patterns ("AI slop"). Strips self-explanatory comments while preserving step markers, background context, and architectural decisions.
disable-model-invocation: true
metadata:
  version: "0.1.0"
---

# Unslop AI Codebase (`unslop-ai-codebase`)

## Purpose
Edit codebases, documentation, commit messages, PR descriptions, and inline comments to eliminate AI-generated patterns ("slop"). Rewrite text to preserve the exact technical meaning and match the intended engineering tone, while pruning redundant code comments and keeping valuable context.

---

## Part 1: Codebase Comment Rules (Prune vs. Preserve)

Scan all comments and docstrings in the target files and apply the **"Why vs. What"** filter.

### 1. REMOVE: Self-Explanatory & AI-Artifact Comments
Delete comments that merely restate what the code literally does or leak LLM conversational habits:
- **Line-by-line narration:**
  - *Bad:* `// Check if user is nil` above `if user == nil`
  - *Bad:* `// Increment counter by 1` above `counter++`
  - *Bad:* `// Return the response` above `return resp`
- **Redundant type/signature restatements:**
  - *Bad:* Docstrings that repeat the function name and parameter types without adding behavioral nuance (e.g., `/** Gets the user by ID. @param id The ID. @returns The user. */`).
- **LLM conversational leftovers & placeholders:**
  - *Bad:* `// Here we implement the logic for...`
  - *Bad:* `// Rest of your code remains the same`
  - *Bad:* `// Updated to handle edge cases seamlessly`
- **Obvious section dividers on tiny blocks:**
  - *Bad:* `// --- Variables ---`, `// --- Helper Functions ---` in short, readable files.

### 2. PRESERVE: Steps, Background, and Decisions
Keep (and if wordy, tighten) comments that capture information the code itself cannot express:
- **Multi-step workflow markers:**
  - Keep numbered or logical phase markers that orient the reader in complex routines (e.g., `// Step 1: Validate cryptographic nonce`, `// Step 2: Acquire distributed lock before mutating state`).
- **Background & Domain Context:**
  - Business rules, protocol quirks, third-party API limitations, or links to RFCs/tickets (e.g., `// Stripe webhook retries up to 72h; idempotency key must outlive window`).
- **Architectural & Trade-off Decisions ("Why not X?"):**
  - Explanations of why a seemingly suboptimal or unusual approach was chosen (e.g., `// Using linear scan instead of a map here because N <= 8 and avoids heap allocation on the hot path`).
- **Non-obvious invariants, edge cases, and gotchas:**
  - Concurrency assumptions, lock ordering, memory ownership, or subtle regex/math behavior.
- **Compiler, Linter, and Tooling Pragmas (NEVER TOUCH):**
  - `//nolint`, `//go:build`, `//go:generate`, `# noqa`, `# type: ignore`, `// @ts-expect-error`, `/* istanbul ignore next */`, etc.

---

## Part 2: Text & Documentation De-Slopping

Scan comments, READMEs, ADRs, commit messages, and UI strings for the AI writing patterns below, then rewrite them into direct, concrete prose.

### Pattern 1: AI Vocabulary & Buzzwords
- **Scan for:** *delve, tapestry, testament, landscape, paradigm, synergy, seamless / seamlessly, robust, leverage (as a verb for "use"), utilize, foster, pivotal, crucial, paramount, underscore, showcase, overarching, intricate, multifaceted, embark, realm, beacon, game-changer, cutting-edge, state-of-the-art, elevate, streamline, holistic.*
- **Rewrite rule:** Replace with plain, concrete verbs and nouns (`use` instead of `leverage/utilize`, state specific failure modes handled instead of calling it `robust` or `seamless`).

### Pattern 2: Throat-Clearing Openers & Meta-Commentary
- **Scan for:**
  - *"In the fast-paced world of..."*, *"In today's modern software landscape..."*
  - *"It is important to note that..."*, *"It is worth mentioning that..."*
  - *"Let's dive into..."*, *"In this section, we will explore..."*
- **Rewrite rule:** Delete the preamble entirely. Start with the subject and action.

### Pattern 3: Formulaic Contrast & Rhetorical Structures
- **Scan for:**
  - *"Not only [X], but also [Y]"* / *"It's not just [X]; it's [Y]"*
  - *"Whether you're [A], [B], or [C], this module..."*
  - *"By leveraging [X], we can ensure [Y], ultimately leading to [Z]."*
  - Participial tail clauses tacked onto the end of sentences: *"...ensuring a seamless experience"*, *"...fostering maintainability and scalability"*, *"...paving the way for future enhancements."*
- **Rewrite rule:** State cause and effect directly. Cut the trailing participial fluff.

### Pattern 4: Compulsive Rule-of-Three & Synonym Cycling
- **Scan for:** Triple adjective/noun stacks used for rhythm rather than precision (e.g., *"fast, reliable, and scalable"*, *"clear, concise, and maintainable"*).
- **Rewrite rule:** Keep only the attributes that are measurably true and relevant to the context.

### Pattern 5: Empty Summary Outros
- **Scan for:** Concluding paragraphs starting with *"In conclusion,"*, *"In summary,"*, *"Overall, this architecture provides a solid foundation for..."*, or *"By following these steps, you will successfully..."*
- **Rewrite rule:** Delete the summary paragraph. End when the technical information ends.

---

## Part 3: Execution Workflow

When invoked on a file, diff, or text block:

1. **Identify Target Scope & Tone:**
   - Match the surrounding codebase's voice (terse kernel-style, standard Go/Rust doc style, pragmatic product-engineering prose, etc.).
2. **Scan & Classify:**
   - Flag self-explanatory comments for deletion.
   - Flag step markers, background context, and decision comments for preservation (and tighten their phrasing if they contain AI fluff).
   - Flag prose/documentation matching Patterns 1–5.
3. **Rewrite & Prune:**
   - Preserve 100% of runtime behavior, public signatures, and tooling directives.
   - Keep every factual detail, constraint, metric, and edge-case note intact while stripping filler words.
4. **Report Changes Briefly:**
   - Summarize what was removed (e.g., *"Removed 14 redundant narration comments; kept 3 step markers and the retry-backoff decision note; rewrote README intro to remove AI buzzwords"*).

## Mandatory Verification Step
Before completing a task that involves this skill, you MUST validate the rewritten files using the bundled script (run from this skill's directory; paths are relative to the skill root):
```bash
# check a single file after rewriting
bash scripts/check.sh "<file-path>"

# check a whole diff of rewritten files
git diff --name-only | xargs -n1 bash scripts/check.sh
```
The validator confirms no rewritten file lost its tooling pragmas (`//nolint`, `# noqa`, `# type: ignore`, `// @ts-expect-error`, `/* istanbul ignore next */`, `//go:build`, `//go:generate`) and that the rewrite did not alter runtime code structure.
If the script exits with a non-zero code, read `stderr`, restore the missing directive or revert the unintended code change, and re-run. Retry at most 5 times; if it still fails, stop retrying and rely on your own judgment (proceed with stated reasoning, or ask the user) instead of looping forever.

## Quick Before / After Example

### Before (Slop)
```ts
/**
 * This function seamlessly leverages the user repository to fetch and validate
 * a user profile, ensuring a robust and secure authentication flow.
 */
async function authenticateUser(userId: string, token: string): Promise<User> {
  // Check if userId or token is missing
  if (!userId || !token) {
    // Throw an error if validation fails
    throw new AuthError("Missing credentials");
  }

  // Step 1: Fetch the user from the database
  const user = await userRepo.findById(userId);

  // Check if user exists
  if (!user) {
    throw new AuthError("User not found");
  }

  // Step 2: Verify token using constant-time comparison.
  // It is important to note that we utilize timingSafeEqual here not just for
  // security, but to foster resilience against sophisticated timing attacks.
  const isValid = timingSafeEqual(Buffer.from(user.token), Buffer.from(token));

  // Return the user if valid, otherwise throw an error
  if (!isValid) {
    throw new AuthError("Invalid token");
  }

  return user;
}
```

### After (Unslopped)
```ts
async function authenticateUser(userId: string, token: string): Promise<User> {
  if (!userId || !token) {
    throw new AuthError("Missing credentials");
  }

  // Step 1: Fetch user record
  const user = await userRepo.findById(userId);
  if (!user) {
    throw new AuthError("User not found");
  }

  // Step 2: Verify token.
  // Decision: Use timingSafeEqual to prevent side-channel timing attacks on token length/prefix.
  const isValid = timingSafeEqual(Buffer.from(user.token), Buffer.from(token));
  if (!isValid) {
    throw new AuthError("Invalid token");
  }

  return user;
}
```
