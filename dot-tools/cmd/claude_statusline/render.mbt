// Renders the Claude Code status line on one line; lower-priority segments are dropped when the terminal is narrow.

///|
let green : String = "\u{1b}[38;2;151;201;195m"

///|
let yellow : String = "\u{1b}[38;2;229;192;123m"

///|
let red : String = "\u{1b}[38;2;224;108;117m"

///|
let gray : String = "\u{1b}[38;2;74;88;92m"

///|
let dim : String = "\u{1b}[2m"

///|
let reset : String = "\u{1b}[0m"

///|
let separator : String = gray + " │ " + reset

///|
let separator_width : Int32 = 3

///|
/// The output for input that cannot be read.
let unknown : String = "🤖 Unknown\n" + dim + "---" + reset

///|
/// Renders the status line for `input`; `now` is in seconds since the epoch and a `width` of 0 means no limit.
fn render(
  input : Input,
  branch : String,
  width : Int32,
  now : Double,
) -> String {
  let segments = ["🤖 " + input.model]
  let context = clamp(input.context_percentage)
  segments.push("📊 \{threshold_color(context)}\{context}%\{reset}")
  segments.push(
    rate("5h", input.five_hour, now) + " " + rate("7d", input.seven_day, now),
  )
  if input.worktree != "" {
    let original = if input.original_branch != "" {
      " ← " + input.original_branch
    } else {
      ""
    }
    segments.push("🌳 " + input.worktree + original)
  } else if branch != "" {
    segments.push("🔀 " + branch)
  }
  if input.lines_added > 0 || input.lines_removed > 0 {
    segments.push(
      "\{green}+\{input.lines_added}/-\{input.lines_removed}\{reset}",
    )
  }
  join_segments(segments, width)
}

///|
/// ○ for 0%, then ◔, ◑, ◕ and ● at about 25% steps.
fn ring(percentage : Int32) -> String {
  let rings = ["○", "◔", "◑", "◕", "●"]
  rings[@cmp.minimum((percentage + 12) / 25, 4)]
}

///|
fn rate(label : String, limit : RateLimit, now : Double) -> String {
  guard limit.used_percentage is Some(used) && used >= 0.0 else {
    return "\{label} \{dim}-\{reset}"
  }
  let percentage = clamp(used)
  let until = match limit.resets_at {
    Some(resets_at) => "(" + time_until(resets_at - now) + ")"
    None => ""
  }
  "\{label} \{threshold_color(percentage)}\{ring(percentage)} \{percentage}%\{until}\{reset}"
}

///|
fn threshold_color(percentage : Int32) -> String {
  if percentage >= 80 {
    red
  } else if percentage >= 50 {
    yellow
  } else {
    green
  }
}

///|
/// Rounds half away from zero, as Go's `math.Round`, then limits to 0..=100.
fn clamp(value : Double) -> Int32 {
  let rounded = if value >= 0.0 {
    (value + 0.5).floor()
  } else {
    (value - 0.5).ceil()
  }
  if rounded <= 0.0 {
    0
  } else if rounded >= 100.0 {
    100
  } else {
    rounded.to_int()
  }
}

///|
fn time_until(seconds : Double) -> String {
  guard seconds > 0.0 else { return "now" }
  let total_hours = (seconds / 3600.0).to_int()
  let days = total_hours / 24
  let hours = total_hours % 24
  let minutes = (seconds / 60.0).to_int() % 60
  if days > 0 {
    "\{days}d\{hours}h"
  } else if hours > 0 {
    let padded = if minutes < 10 { "0\{minutes}" } else { "\{minutes}" }
    "\{hours}h\{padded}m"
  } else {
    "\{minutes}m"
  }
}

///|
/// Keeps the segments that fit in `width` columns, and always the first one.
fn join_segments(segments : Array[String], width : Int32) -> String {
  if width <= 0 {
    return segments.join(separator)
  }
  let kept = []
  let mut used = 0
  for segment in segments {
    let need = @text.visible_width(segment) +
      (if kept.is_empty() { 0 } else { separator_width })
    if used + need > width {
      break
    }
    kept.push(segment)
    used += need
  }
  if kept.is_empty() {
    kept.push(segments[0])
  }
  kept.join(separator)
}

///|
extern "C" fn terminal_columns(fd : Int32) -> Int32 = "agent_hooks_terminal_columns"

///|
/// `COLUMNS` when it is a positive number, else the width of the terminal on standard output, else 0.
fn terminal_width() -> Int32 {
  if @env.get_env_var("COLUMNS") is Some(columns) {
    let value = @string.parse_int(columns) catch { _ => 0 }
    if value > 0 {
      return value
    }
  }
  terminal_columns(1)
}

///|
/// The current branch of the repository at `cwd`, or "" outside one.
async fn current_branch(cwd : String) -> String {
  guard cwd != "" else { return "" }
  let (status, stdout, _) = @process.collect_output(
    "git",
    ["-C", cwd, "--no-optional-locks", "rev-parse", "--abbrev-ref", "HEAD"],
    stdin=@process.redirect_from_file("/dev/null"),
  ) catch {
    _ => return ""
  }
  guard status == 0 else { return "" }
  stdout.text().trim().to_owned() catch {
    _ => ""
  }
}
