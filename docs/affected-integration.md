# Optional local monitoring integration

Install the private agent separately as `~/.local/bin/am-i-affected`.
The public dotfiles provide invocation only; the agent owns collection, transport,
cached status, and scheduling after application.
No credentials are provisioned by dotfiles.

## Invocation contract

`~/bin/affected-agent` invokes the private executable without a shell.
Set `AM_I_AFFECTED_BIN` to an absolute executable path to override its location.
The managed Nix profile and current system tools are added to its `PATH`.

| Public wrapper argument | Private agent argument | Time limit | Result |
| --- | --- | --- | --- |
| `collect-and-push` | `collect-and-push` | 15 minutes | Agent exit status; missing setup succeeds silently |
| `after-apply` | `after-apply` | 2 seconds | Always succeeds; agent must schedule collection and return immediately |
| `status` | `status` | 0.5 seconds | Prints one short cached status line; never collects or calls AI |
| `codex-status` | `status` | 0.5 seconds | Same text in a JSON `systemMessage` |
| `watch-wake` | `watch-wake` | Managed by launchd | Replaces wrapper with private wake observer; missing setup succeeds silently |

Status must include aggregate pending counts and separate Mac/cloud last-success
times. Missing setup is silent; an installed agent that fails or times out shows
unavailable status and unknown times. The wrapper does not store monitoring data.
An agent timeout terminates its process group; scheduled background work from
`after-apply` must run in its own session without inherited output pipes.

## Personal Mac

chezmoi generates `~/Library/LaunchAgents/local.am-i-affected.plist` and the wrapper.
The job runs at 00:00, 03:00, 06:00, 09:00, 12:00, 15:00, 18:00 and 21:00 local time.
Its calendar timer catches up once on wake when a scheduled time passed during
sleep; it does not run on every wake or wake the Mac itself.
This follows [Apple's calendar scheduling behavior](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html).

The separate `local.am-i-affected-wake` job starts the private `watch-wake` observer
at login. It restarts only after failure, with a 60-second throttle. The private
command must exit successfully when not configured or when Swift is unavailable
to avoid a restart loop. Wake detection and collection stay in the private agent.

After reviewing and applying these files, load the job manually:

```sh
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/local.am-i-affected.plist
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/local.am-i-affected-wake.plist
```

To stop it:

```sh
launchctl bootout "gui/$(id -u)/local.am-i-affected"
launchctl bootout "gui/$(id -u)/local.am-i-affected-wake"
```

The final chezmoi after-script invokes `after-apply` after successful application.
`dotctl sync-nix-profile` also invokes it after a successful profile update.
For updates applied separately, such as a nix-darwin switch, invoke
`~/bin/affected-agent after-apply` only after the update succeeds.
An absent or failed agent cannot fail dotfiles application.

Claude Code displays the cached line above the existing status line, using its
[supported multiline output](https://code.claude.com/docs/en/statusline).
Codex displays it through the existing `SessionStart` hook using the documented
[`systemMessage` output](https://learn.chatgpt.com/docs/hooks).
Restart Codex and trust the updated hook through `/hooks` before relying on it.
Actual host display, launchd execution, wake behavior, and private transport need
manual acceptance after installation.
Every-wake execution depends on the private observer and remains unverified until
both the agent and this job have been installed and tested on the Mac.

## Work Mac

chezmoi generates neither the wrapper nor either LaunchAgent, and adds no monitoring
startup hook. The Claude remediation skill is available for local checks on both
machine types. Work-Mac application of shared changes remains a manual check.
