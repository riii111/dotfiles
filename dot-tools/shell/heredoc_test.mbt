///|
test "strip_heredocs drops bodies and keeps the commands around them" {
  let cases : Array[(String, String)] = [
    ("cat <<EOF\nbody\nEOF\nls", "cat <<EOF\nls"),
    ("cat <<-'E F'\n\tbody\n\tE F\nls", "cat <<-'E F'\nls"),
    ("cat <<A; cat <<\\B\na\nA\nb\nB\nls", "cat <<A; cat <<\\B\nls"),
    ("echo '<<EOF'\nls\nEOF", "echo '<<EOF'\nls\nEOF"),
    ("cat <<EOF\nno delimiter line", "cat <<EOF\nno delimiter line"),
  ]
  for case in cases {
    let (command, expected) = case
    assert_eq(@shell.strip_heredocs(command), expected)
  }
}
