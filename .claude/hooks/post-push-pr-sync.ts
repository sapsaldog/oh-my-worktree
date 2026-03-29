import { execSync } from "child_process";
import { readFileSync } from "fs";

interface HookInput {
  tool_name: string;
  tool_input: { command?: string };
  tool_response?: unknown;
}

interface HookOutput {
  continue: boolean;
  hookSpecificOutput?: {
    hookEventName: string;
    additionalContext: string;
  };
}

function output(result: HookOutput): void {
  process.stdout.write(JSON.stringify(result));
}

function run(): void {
  const raw = readFileSync("/dev/stdin", "utf-8");
  const input: HookInput = JSON.parse(raw);
  const command = input.tool_input.command ?? "";

  // Only trigger on git push commands (excluding tag pushes)
  if (!/git\s+push/.test(command)) return output({ continue: true });
  if (/git\s+push\s+.*--tags|git\s+push\s+.*tag\s/.test(command)) {
    return output({ continue: true });
  }

  // Check for open PR on current branch
  let prJson: string;
  try {
    prJson = execSync("gh pr view --json number,title,body,url", {
      encoding: "utf-8",
      timeout: 15_000,
    });
  } catch {
    return output({ continue: true });
  }

  const pr = JSON.parse(prJson);

  const context = `[PR Sync] Open PR detected after push: #${pr.number} (${pr.url})

Current title: ${pr.title}

Current body:
${pr.body}

---
Review the PR's actual changes (commits, diff) against the current title and body above.
If there is a meaningful gap, update the PR title and/or body using "gh pr edit".
If the title and body already accurately reflect the changes, do nothing.`;

  output({
    continue: true,
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: context,
    },
  });
}

run();
