file.copy"test/edit_insert_line_test.txt"{
  dest  = "test/tmp/edit_insert_line_test.txt",
  force = "true"
}

edit.insert_line"test/tmp/edit_insert_line_test.txt"{
  plain   = "true",
  before_pattern = "true",
  pattern = "father",
  line    = "mother",
  diff    = "true"
}
