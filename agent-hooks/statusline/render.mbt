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
pub let unknown : String = "🤖 Unknown\n" + dim + "---" + reset

///|
/// Renders the status line for `input`; `now` is in seconds since the epoch and a `width` of 0 means no limit.
pub fn render(
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
    let need = visible_width(segment) +
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
/// The terminal columns `text` takes, without ANSI escape sequences.
fn visible_width(text : String) -> Int32 {
  let mut width = 0
  let mut escaped = false
  for char in text {
    if escaped {
      escaped = !char.is_ascii_alphabetic()
      continue
    }
    if char == '\u{1b}' {
      escaped = true
      continue
    }
    width += char_width(char)
  }
  width
}

///|
/// Two columns for emoji, CJK scripts and full-width forms; none for control characters and joiners.
fn char_width(char : Char) -> Int32 {
  let code = char.to_int()
  if code < 0x20 || code == 0xFE0F || code == 0x200D {
    return 0
  }
  if (code >= 0x1F300 && code <= 0x1FAFF) ||
    is_east_asian_script(code) ||
    (code >= 0xFF01 && code <= 0xFF60) ||
    (code >= 0xFFE0 && code <= 0xFFE6) {
    2
  } else {
    1
  }
}

///|
/// The Han, Hangul, Katakana and Hiragana script ranges of Go's `unicode` tables.
fn is_east_asian_script(code : Int32) -> Bool {
  match code {
    0x1100..<=0x11FF
    | 0x2E80..<=0x2E99
    | 0x2E9B..<=0x2EF3
    | 0x2F00..<=0x2FD5
    | 0x3005
    | 0x3007
    | 0x3021..<=0x3029
    | 0x302E..<=0x302F
    | 0x3038..<=0x303B
    | 0x3041..<=0x3096
    | 0x309D..<=0x309F
    | 0x30A1..<=0x30FA
    | 0x30FD..<=0x30FF
    | 0x3131..<=0x318E
    | 0x31F0..<=0x31FF
    | 0x3200..<=0x321E
    | 0x3260..<=0x327E
    | 0x32D0..<=0x32FE
    | 0x3300..<=0x3357
    | 0x3400..<=0x4DBF
    | 0x4E00..<=0x9FFF
    | 0xA960..<=0xA97C
    | 0xAC00..<=0xD7A3
    | 0xD7B0..<=0xD7C6
    | 0xD7CB..<=0xD7FB
    | 0xF900..<=0xFA6D
    | 0xFA70..<=0xFAD9
    | 0xFF66..<=0xFF6F
    | 0xFF71..<=0xFF9D
    | 0xFFA0..<=0xFFBE
    | 0xFFC2..<=0xFFC7
    | 0xFFCA..<=0xFFCF
    | 0xFFD2..<=0xFFD7
    | 0xFFDA..<=0xFFDC
    | 0x16FE2..<=0x16FE3
    | 0x16FF0..<=0x16FF1
    | 0x1AFF0..<=0x1B122
    | 0x1B132
    | 0x1B150..<=0x1B152
    | 0x1B155
    | 0x1B164..<=0x1B167
    | 0x1F200
    | 0x20000..<=0x2A6DF
    | 0x2A700..<=0x2EBE0
    | 0x2F800..<=0x2FA1D
    | 0x30000..<=0x323AF => true
    _ => false
  }
}

///|
extern "C" fn terminal_columns(fd : Int32) -> Int32 = "agent_hooks_terminal_columns"

///|
/// `COLUMNS` when it is a positive number, else the width of the terminal on standard output, else 0.
pub fn terminal_width() -> Int32 {
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
pub async fn current_branch(cwd : String) -> String {
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
