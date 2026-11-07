///|
test "strip_heredocs drops bodies and keeps the commands around them" {
  let cases : Array[(String, String)] = [
    ("cat <<EOF\nbody\nEOF\nls", "cat <<EOF\nls"),
    ("cat <<-'E F'\n\tbody\n\tE F\nls", "cat <<-'E F'\nls"),
    ("cat <<A; cat <<\\B\na\nA\nb\nB\nls", "cat <<A; cat <<\\B\nls"),
    ("echo '<<EOF'\nls\nEOF", "echo '<<EOF'\nls\nEOF"),
    ("cat <<EOF\nno delimiter line", "cat <<EOF\nno delimiter line"),
    // Bodies stay when something could run them; `.` counts only as a command.
    ("bash <<EOF\nls\nEOF", "bash <<EOF\nls\nEOF"),
    ("cat <<EOF | /bin/sh\nls\nEOF", "cat <<EOF | /bin/sh\nls\nEOF"),
    ("X=1 . /dev/stdin <<EOF\nls\nEOF", "X=1 . /dev/stdin <<EOF\nls\nEOF"),
    ("git add . && cat <<EOF\nls\nEOF", "git add . && cat <<EOF\n"),
  ]
  for case in cases {
    let (command, expected) = case
    assert_eq(@shell.strip_heredocs(command), expected)
  }
}
