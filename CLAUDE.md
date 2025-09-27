# Claude Code Configuration for Sounder Project

## IMPORTANT: Agent Usage for Context Management

This project is very large and frequently exceeds Claude's context size limit. To manage this:

### Required Behavior
1. **ALWAYS use MCP agents first** for any operations they can handle
2. **Agent priority order:**
   - First try: `mini-agent`
   - If fails: `codex-shim`
   - Last resort: Direct tool usage only if both fail

3. **Include in every agent request:**
   - "Provide concise output"
   - "Minimize tokens"
   - "Be brief"

### Why This Matters
- Prevents context overflow errors
- Allows longer, more productive sessions
- Reduces token consumption by 70-90%

### Example
```bash
# CORRECT approach:
"Use mini-agent to find all Swift files and list them concisely"

# WRONG approach:
"Let me use Glob to find files..." (uses too much context)
```

This configuration persists across Claude restarts.