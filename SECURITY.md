# Security

Tendbar changes `~/.claude/settings.json`, runs a helper on every Claude Code hook event and listens on a local Unix
socket, so mistakes here matter. Please report a security problem privately through
[GitHub's private vulnerability reporting](https://github.com/gruntz12/tendbar/security/advisories/new), not in a
public issue.

Useful to include: the Tendbar version, what an attacker needs (another local user, a malicious repository, a crafted
transcript…) and what they gain.

Examples of what counts:

- a way to make Tendbar or `tendbar-hook` run commands or write files it should not
- the socket, data folder or settings backups readable or writable by other users
- data the README says never leaves the hook helper (prompts, tool input and output, replies) reaching the app or disk

Only the latest version gets fixes.
